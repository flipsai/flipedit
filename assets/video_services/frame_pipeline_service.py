#!/usr/bin/env python3
import cv2
import numpy as np
import logging
import functools
from typing import List, Dict, Any, Optional

# Import the services we've created
from .timeline_state_service import TimelineStateService
from .video_source_service import VideoSourceService
from .frame_transform_service import FrameTransformService
from .compositing_service import CompositingService
from .encoding_service import EncodingService
from .frame_cache_service import FrameCacheService # For caching individual processed clip frames

logger = logging.getLogger(__name__)

class FramePipelineService:
    """
    Orchestrates the generation of a final, encoded frame by coordinating
    various specialized services.
    Manages a cache for fully rendered and encoded frames.
    """
    def __init__(
        self,
        timeline_state_service: TimelineStateService,
        video_source_service: VideoSourceService,
        frame_transform_service: FrameTransformService,
        compositing_service: CompositingService,
        encoding_service: EncodingService,
        # Optional: Cache for intermediate transformed frames (output of FrameTransformService)
        intermediate_frame_cache_service: Optional[FrameCacheService] = None, 
        # Cache for final rendered & encoded frames (output of EncodingService)
        final_frame_cache_max_entries: int = 256 
    ):
        self.timeline_state_service = timeline_state_service
        self.video_source_service = video_source_service
        self.frame_transform_service = frame_transform_service
        self.compositing_service = compositing_service
        self.encoding_service = encoding_service
        self.intermediate_frame_cache = intermediate_frame_cache_service

        # LRU Cache for final rendered (encoded) frames
        # Key: Hashable timeline state from TimelineStateService + frame_index
        # Value: Encoded frame (bytes)
        self._final_frame_lru_cache = functools.lru_cache(maxsize=final_frame_cache_max_entries)(
            self._generate_and_encode_frame_for_caching
        )
        logger.info("FramePipelineService initialized.")

    def _generate_and_encode_frame_for_caching(
        self, 
        frame_index: int, 
        timeline_state_hashable: tuple # From TimelineStateService
    ) -> Optional[bytes]:
        """
        Internal method that performs the actual frame generation and encoding.
        This method's results are cached by _final_frame_lru_cache.
        The timeline_state_hashable ensures that if the timeline changes,
        the cache key changes.
        """
        # Unpack relevant parts from the hashable state if needed, or rely on
        # the TimelineStateService instance to have the current state.
        # For this example, we'll use the instance directly.
        canvas_width = self.timeline_state_service.canvas_width
        canvas_height = self.timeline_state_service.canvas_height
        current_videos = self.timeline_state_service.current_videos
        total_frames = self.timeline_state_service.total_frames # Overall timeline duration

        if not current_videos:
            logger.debug(f"No videos in timeline for frame {frame_index}. Generating blank frame.")
            blank_canvas = self.compositing_service.create_blank_canvas(canvas_width, canvas_height)
            # Add "No videos loaded" text or similar
            cv2.putText(blank_canvas, f"No Clips (F:{frame_index})", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (200,200,200),1)
            return self.encoding_service.encode_frame_to_jpeg(blank_canvas)

        base_canvas = self.compositing_service.create_blank_canvas(canvas_width, canvas_height)
        
        processed_frames_for_compositing = []
        any_video_rendered = False

        for clip_info in current_videos:
            video_path = clip_info.get('sourcePath') or clip_info.get('source_path')
            if not video_path:
                logger.warning("Skipping clip with no sourcePath.")
                continue

            # Determine if clip is active at this frame_index
            # Assuming 'startTimeOnTrackMs' and 'endTimeOnTrackMs' are converted to frame numbers
            # or compared against frame_index * (ms_per_frame)
            # For simplicity, let's assume clip_info contains calculated start/end frames for the track
            clip_start_frame = clip_info.get('start_frame_calc', 0) 
            clip_end_frame = clip_info.get('end_frame_calc', total_frames)

            if not (clip_start_frame <= frame_index < clip_end_frame):
                continue # Clip is not active at this timeline frame

            source_start_frame = clip_info.get('source_start_frame_calc', 0)
            frame_offset_in_clip = frame_index - clip_start_frame
            current_source_frame_index = source_start_frame + frame_offset_in_clip
            
            transformed_frame_data = None
            intermediate_cache_key = None

            if self.intermediate_frame_cache:
                # Key needs to be unique for the source frame AND its specific transformations
                # This could include video_path, current_source_frame_index, and a hash of relevant transform properties.
                # Use new direct transform properties for the cache key.
                pos_x = clip_info.get('previewPositionX') # Using camelCase as per db_access.py output
                pos_y = clip_info.get('previewPositionY')
                width = clip_info.get('previewWidth')
                height = clip_info.get('previewHeight')
                # Still consider flip if it's a separate property, e.g., from metadata
                flip_val = clip_info.get('metadata',{}).get('flip', None)
                
                # Create a stable tuple for the cache key part
                transform_tuple = (
                    f"{pos_x:.2f}" if pos_x is not None else "None",
                    f"{pos_y:.2f}" if pos_y is not None else "None",
                    f"{width:.2f}" if width is not None else "None",
                    f"{height:.2f}" if height is not None else "None",
                )

                intermediate_cache_key = f"{video_path}:{current_source_frame_index}:{transform_tuple}:{flip_val}"
                cached_intermediate_frame_data_tuple = self.intermediate_frame_cache.get_frame(intermediate_cache_key)
                if cached_intermediate_frame_data_tuple:
                    if isinstance(cached_intermediate_frame_data_tuple, tuple) and len(cached_intermediate_frame_data_tuple) == 5:
                        transformed_frame_data = cached_intermediate_frame_data_tuple
                        logger.debug(f"Intermediate cache HIT for {intermediate_cache_key}")


            if transformed_frame_data is None:
                raw_frame = self.video_source_service.get_frame(video_path, current_source_frame_index)
                if raw_frame is None:
                    logger.warning(f"Could not get raw frame {current_source_frame_index} from {video_path}")
                    continue
                
                # Transform frame
                processed_frame, x, y, w, h = self.frame_transform_service.transform_frame(
                    raw_frame, clip_info, canvas_width, canvas_height
                )
                if processed_frame is None:
                    logger.warning(f"Failed to transform frame {current_source_frame_index} from {video_path}")
                    continue
                transformed_frame_data = (processed_frame, x, y, w, h)

                if self.intermediate_frame_cache and intermediate_cache_key:
                    # Cache the tuple (processed_frame, x, y, w, h)
                    self.intermediate_frame_cache.put_frame(intermediate_cache_key, transformed_frame_data) 
                    logger.debug(f"Intermediate cache PUT for {intermediate_cache_key}")


            if transformed_frame_data is not None: # Check if processed_frame is valid
                 processed_frames_for_compositing.append(transformed_frame_data)
                 any_video_rendered = True


        if not any_video_rendered and current_videos: # Had clips, but none were visible/renderable
            cv2.putText(base_canvas, f"No Visible Clips (F:{frame_index})", (10, 50), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (180,180,180),1)
        
        final_composited_frame = self.compositing_service.composite_frames(
            base_canvas, processed_frames_for_compositing
        )

        # Add global overlays, e.g., frame number
        cv2.putText(final_composited_frame, f"F:{frame_index}", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (200,200,200),1)

        return self.encoding_service.encode_frame_to_jpeg(final_composited_frame)

    def get_encoded_frame(self, frame_index: int) -> Optional[bytes]:
        """
        Retrieves an encoded (JPEG) frame for the given timeline frame_index.
        Uses the LRU cache for final frames.
        """
        # Get the current hashable state of the timeline
        # This state includes canvas dimensions, total_frames, and a hashable
        # representation of all video clips and their relevant properties.
        current_timeline_hash = self.timeline_state_service.get_hashable_timeline_state()
        
        # The LRU cache uses frame_index and the timeline_state_hash as its key parts.
        return self._final_frame_lru_cache(frame_index, current_timeline_hash)

    def clear_all_caches(self):
        """Clears all underlying caches."""
        logger.info("Clearing all caches in FramePipelineService.")
        self._final_frame_lru_cache.cache_clear()
        if self.intermediate_frame_cache:
            self.intermediate_frame_cache.clear_cache()
        # Services below pipeline usually manage their own caches if needed (e.g. VideoSourceService)
        # but we can call them explicitly if direct control is desired.
        self.video_source_service.clear_cache() 
        # TimelineStateService might have internal caches for its hashing, clear them too.
        self.timeline_state_service.clear_caches()


if __name__ == '__main__':
    logging.basicConfig(level=logging.DEBUG)

    # Setup dummy services
    timeline_state = TimelineStateService()
    video_source = VideoSourceService() # Will create dummy video if run directly
    frame_transform = FrameTransformService()
    compositing = CompositingService()
    encoding = EncodingService()
    intermediate_cache = FrameCacheService(max_cache_entries=50) # Cache for transformed clip frames

    pipeline = FramePipelineService(
        timeline_state, video_source, frame_transform, 
        compositing, encoding, intermediate_cache
    )

    # Create a dummy video file for VideoSourceService if it doesn't exist
    dummy_video_path = "dummy_test_video.mp4" # Matches VideoSourceService's __main__
    if not os.path.exists(dummy_video_path):
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        out_vid = cv2.VideoWriter(dummy_video_path, fourcc, 30.0, (100, 100))
        for i in range(90):
            f = np.zeros((100, 100, 3), dtype=np.uint8)
            cv2.putText(f, str(i), (10, 50), cv2.FONT_HERSHEY_SIMPLEX, 1, (255,0,0), 2)
            out_vid.write(f)
        out_vid.release()
        logger.info(f"Main: Created dummy video: {dummy_video_path}")


    # Sample timeline data
    sample_clips = [
        {
            "clipId": "c1", "sourcePath": dummy_video_path, 
            "start_frame_calc": 0, "end_frame_calc": 60, # Active for frame 0-59
            "source_start_frame_calc": 0, # Start from beginning of dummy video
            "metadata": {"previewRect": {"left": 10, "top": 10, "width": 300, "height": 200}}
        },
        {
            "clipId": "c2", "sourcePath": dummy_video_path,
            "start_frame_calc": 30, "end_frame_calc": 90, # Active for frame 30-89
            "source_start_frame_calc": 20, # Start from frame 20 of dummy video
            "metadata": {"previewRect": {"left": 350, "top": 250, "width": 400, "height": 300}, "flip": "vertical"}
        }
    ]
    timeline_state.update_timeline_data(sample_clips, 90) # 90 total frames in timeline
    timeline_state.update_canvas_dimensions(1280, 720)

    # Test getting a frame
    target_frame_idx = 35
    encoded_frame = pipeline.get_encoded_frame(target_frame_idx)
    if encoded_frame:
        logger.info(f"Successfully got encoded frame {target_frame_idx}. Size: {len(encoded_frame)} bytes.")
        # with open(f"frame_{target_frame_idx}.jpg", "wb") as f:
        #     f.write(encoded_frame)
    else:
        logger.error(f"Failed to get encoded frame {target_frame_idx}.")

    # Test caching: get same frame again
    encoded_frame_cached = pipeline.get_encoded_frame(target_frame_idx)
    if encoded_frame_cached:
        logger.info(f"Got encoded frame {target_frame_idx} from cache. Size: {len(encoded_frame_cached)} bytes.")
        assert encoded_frame == encoded_frame_cached

    # Change timeline state (e.g., a clip's previewRect)
    sample_clips["metadata"]["previewRect"]["width"] = 320 
    timeline_state.update_timeline_data(sample_clips, 90) # This changes the timeline_state_hash

    encoded_frame_after_change = pipeline.get_encoded_frame(target_frame_idx)
    if encoded_frame_after_change:
        logger.info(f"Got encoded frame {target_frame_idx} after change. Size: {len(encoded_frame_after_change)} bytes.")
        assert encoded_frame != encoded_frame_after_change # Should be different due to re-render

    pipeline.clear_all_caches()
    logger.info("FramePipelineService test complete.")

    # if os.path.exists(dummy_video_path):
    #    os.remove(dummy_video_path)