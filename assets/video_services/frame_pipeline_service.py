#!/usr/bin/env python3
import cv2
import numpy as np
import logging
from typing import List, Dict, Any, Optional # functools import removed

# Import the services we've created
from .timeline_state_service import TimelineStateService
from .video_source_service import VideoSourceService
from .frame_transform_service import FrameTransformService
from .compositing_service import CompositingService
from .encoding_service import EncodingService

logger = logging.getLogger(__name__)

class FramePipelineService:
    """
    Orchestrates the generation of a final, encoded frame by coordinating
    various specialized services.
    Frames are generated on-the-fly without caching.
    """
    def __init__(
        self,
        timeline_state_service: TimelineStateService,
        video_source_service: VideoSourceService,
        frame_transform_service: FrameTransformService,
        compositing_service: CompositingService,
        encoding_service: EncodingService
        # intermediate_frame_cache_service parameter removed
        # final_frame_cache_max_entries parameter removed
    ):
        self.timeline_state_service = timeline_state_service
        self.video_source_service = video_source_service
        self.frame_transform_service = frame_transform_service
        self.compositing_service = compositing_service
        self.encoding_service = encoding_service
        # self.intermediate_frame_cache attribute removed
        # self._final_frame_lru_cache attribute removed
        self._debug_verbose = False  # Flag to control detailed debug output
        logger.info("FramePipelineService initialized (no caching).")

    def set_debug_verbosity(self, verbose: bool):
        """Set debug verbosity level"""
        self._debug_verbose = verbose
        logger.info(f"FramePipelineService debug verbosity set to: {verbose}")

    def _generate_and_encode_frame( # Renamed from _generate_and_encode_frame_for_caching
        self,
        frame_index: int
        # timeline_state_hashable parameter removed
    ) -> Optional[bytes]:
        """
        Internal method that performs the actual frame generation and encoding.
        Called directly by get_encoded_frame.
        """
        # Use the TimelineStateService instance directly to get current state.
        canvas_width = self.timeline_state_service.canvas_width
        canvas_height = self.timeline_state_service.canvas_height
        current_videos = self.timeline_state_service.current_videos
        total_frames = self.timeline_state_service.total_frames # Overall timeline duration
        
        # Log only periodically to reduce log volume
        if frame_index % 30 == 0 or self._debug_verbose:
            logger.info(f"Processing frame {frame_index} with canvas {canvas_width}x{canvas_height}, {len(current_videos)} clips")
        
        # Pre-process clips - check for small preview dimensions and update them
        for i, clip in enumerate(current_videos):
            clip_id = clip.get('databaseId', 'unknown')
            clip_path = clip.get('sourcePath', 'unknown')
            preview_width = clip.get('previewWidth')
            preview_height = clip.get('previewHeight')
            
            # Check for default 100x100 dimensions or other small values
            if (preview_width is not None and preview_height is not None and 
                (preview_width <= 100 or preview_height <= 100)):
                # Update with canvas dimensions
                if self._debug_verbose:
                    logger.info(f"Updating small clip dimensions ({preview_width}x{preview_height}) to canvas dimensions for clip {clip_id}")
                clip['previewWidth'] = canvas_width
                clip['previewHeight'] = canvas_height
            
            # Only log clip details in verbose mode
            if self._debug_verbose:
                preview_width = clip.get('previewWidth')
                preview_height = clip.get('previewHeight') 
                logger.info(f"Clip {i} (ID: {clip_id}, Path: {clip_path}) has dimensions: previewWidth={preview_width}, previewHeight={preview_height}")

        if not current_videos:
            if self._debug_verbose:
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
            # intermediate_cache logic removed

            # Always generate frame, no caching lookup
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
        Generates the frame on-the-fly.
        """
        # timeline_state_hashable is no longer used as caching is removed.
        # Directly call the internal generation method.
        # current_timeline_hash = self.timeline_state_service.get_hashable_timeline_state() # Removed
        return self._generate_and_encode_frame(frame_index) # Removed current_timeline_hash

    def clear_all_caches(self):
        """
        Clears caches in underlying services.
        FramePipelineService itself no longer has direct caches.
        """
        logger.info("Clearing caches in underlying services for FramePipelineService.")
        # self._final_frame_lru_cache.cache_clear() # Removed
        # if self.intermediate_frame_cache: # Removed
            # self.intermediate_frame_cache.clear_cache() # Removed
        
        # Services below pipeline usually manage their own caches if needed
        self.video_source_service.clear_cache()
        self.timeline_state_service.clear_caches()


if __name__ == '__main__':
    logging.basicConfig(level=logging.DEBUG)

    # Setup dummy services
    timeline_state = TimelineStateService()
    video_source = VideoSourceService() # Will create dummy video if run directly
    frame_transform = FrameTransformService()
    compositing = CompositingService()
    encoding = EncodingService()

    pipeline = FramePipelineService(
        timeline_state, video_source, frame_transform,
        compositing, encoding # intermediate_cache removed from arguments
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
    # Note: The original test for cache invalidation by changing timeline_state_hash
    # is less relevant now as caching is removed. Frames are always regenerated.
    # We can still test that getting a frame after a state change works.
    if sample_clips: # Ensure sample_clips is not empty before trying to modify
        sample_clips[0]["metadata"]["previewRect"]["width"] = 320 # Corrected to access first element
        timeline_state.update_timeline_data(sample_clips, 90)

    encoded_frame_after_change = pipeline.get_encoded_frame(target_frame_idx)
    if encoded_frame_after_change:
        logger.info(f"Got encoded frame {target_frame_idx} after change. Size: {len(encoded_frame_after_change)} bytes.")
        # The assertion encoded_frame != encoded_frame_after_change might still hold if the content changed.
        # If only metadata changed that didn't affect the visual output of frame 35, they could be identical.
        # For simplicity, we'll assume the change *does* alter the frame.
        if encoded_frame and encoded_frame_after_change: # Ensure both exist before comparing
             assert encoded_frame != encoded_frame_after_change, "Frame content should differ after state change affecting visuals."

    pipeline.clear_all_caches() # This now clears underlying service caches
    logger.info("FramePipelineService test complete.")

    # if os.path.exists(dummy_video_path):
    #    os.remove(dummy_video_path)