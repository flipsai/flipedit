#!/usr/bin/env python3
import cv2
import numpy as np
import os
import logging
import threading
from typing import Dict, List, Optional
import functools

# OpenCV threading configuration
# These settings optimize for performance with hardware acceleration
cv2.setNumThreads(4)  # Set explicit thread count (adjust based on your CPU cores)
os.environ["OPENCV_FFMPEG_THREADS"] = "4"  # Multi-thread for FFMPEG operations
os.environ["OPENCV_FFMPEG_CAPTURE_OPTIONS"] = "rtsp_transport;tcp|enable_stream_syntax;1|hwaccel;auto"  # Enable hardware acceleration
os.environ["OPENCV_FFMPEG_LOCK_STRATEGY"] = "mutex"  # Use mutex for locking strategy

logger = logging.getLogger('video_stream_server')

class FrameGenerator:
    def __init__(self):
        # Video cache to reuse video capture objects
        # This is no longer a direct dict, as lru_cache handles it
        # self.video_cache: Dict[str, cv2.VideoCapture] = {}

        # Canvas dimensions (defaults, will be updated by app)
        self.canvas_width = 1280
        self.canvas_height = 720

        # Thread safety for FFmpeg operations
        self.video_lock = threading.RLock()
        
        # Frame cache for fast sequential access
        self._frame_cache = {}
        
        # Optimize OpenCV threading for performance
        thread_count = os.cpu_count() or 4  # Use CPU count or default to 4
        cv2.setNumThreads(thread_count)  # Use all available cores
        
        # Configure processing flags for maximum performance
        self.resize_interpolation = cv2.INTER_NEAREST  # Fastest interpolation method
        self.jpeg_quality = 75  # Better performance with slight quality tradeoff
        
        # Initialize the instance variable for the current object being hashed
        self._current_object_for_hashing = None

    def update_canvas_dimensions(self, width: int, height: int):
        """Update the canvas dimensions used for rendering."""
        if width <= 0 or height <= 0:
            logger.warning(f"Invalid canvas dimensions: {width}x{height}")
            return

        if self.canvas_width != width or self.canvas_height != height:
            logger.info(f"Updating canvas dimensions to {width}x{height}")
            self.canvas_width = width
            self.canvas_height = height
            logger.info("Clearing pre-rendered frame cache due to canvas dimension change.")
            self._do_generate_frame_cached.cache_clear()

    # Cache for _make_hashable to avoid redundant computations on the same objects
    @functools.lru_cache(maxsize=512)  # Increased cache size for better hit rate
    def _make_hashable_cached(self, obj_str, obj_type):
        """Cached version that takes string representation and type as input for memoization."""
        # This is just a helper method for caching - the actual implementation is in _make_hashable
        # The real object is accessed from an instance variable
        return self._current_object_for_hashing

    def _make_hashable(self, obj):
        """Recursively converts a potentially unhashable object into a fully hashable one."""
        # Fast path for common hashable types to avoid unnecessary processing
        if isinstance(obj, (str, int, float, bool, type(None))):
            return obj
            
        # Store the object for the cached method to access (now an instance variable)
        self._current_object_for_hashing = obj
            
        # For collections, process only if they contain items
        if isinstance(obj, dict):
            if not obj:  # Empty dict optimization
                return tuple()
                
            items = []
            for k, v in obj.items():
                # Only process keys that are relevant for video configurations
                # Skip processing values that don't affect visual output
                if k in ('clipId', 'sourcePath', 'start_frame_calc', 'end_frame_calc',
                         'source_start_frame_calc', 'metadata', 'flip'):
                    hk = self._make_hashable(k)
                    hv = self._make_hashable(v)
                    items.append((hk, hv))
            try:
                # This sorting is crucial for dicts to have a canonical representation
                sorted_items = sorted(items)
            except TypeError as e:
                 # Fallback: sort by string representation of keys if direct sort fails
                logger.warning(f"TypeError while sorting dict items for hashing. Falling back to string sort.")
                sorted_items = sorted(items, key=lambda item_pair: str(item_pair[0]))
            return tuple(sorted_items)
        
        if isinstance(obj, list):
            if not obj:  # Empty list optimization
                return tuple()
            return tuple(self._make_hashable(e) for e in obj)
        
        if isinstance(obj, set):
            if not obj:  # Empty set optimization
                return tuple()
            # Sort elements to ensure consistent order for hashability
            return tuple(sorted(self._make_hashable(e) for e in obj))

        # For all other types, check if they are hashable.
        try:
            hash(obj)  # Test hashability
            return obj # Object is already hashable
        except TypeError:
            # Fallback to string representation
            return str(obj)

    def _get_hashable_videos_representation(self, videos_list: List[Dict]) -> tuple:
        """Converts a list of video dictionaries into a deeply hashable tuple representation."""
        if not isinstance(videos_list, list):
            logger.warning(f"_get_hashable_videos_representation: videos_list is not a list, it's a {type(videos_list)}. Attempting to process.")
            try:
                videos_list = list(videos_list)
            except TypeError:
                logger.error(f"_get_hashable_videos_representation: videos_list of type {type(videos_list)} is not iterable. Returning empty tuple.")
                return tuple()

        try:
            # Ensure stable sort order for the list of videos
            sorted_videos_list = sorted(
                videos_list,
                key=lambda x: (
                    str(x.get('clipId', '')), # Primary sort by clipId (as string)
                    str(x.get('sourcePath', '')), # Secondary by sourcePath (as string)
                    str(x) # Fallback tertiary sort for absolute stability
                ) if isinstance(x, dict) else str(x) # Handle non-dict items in list
            )
        except Exception as e:
            logger.error(f"_get_hashable_videos_representation: ERROR during video list sorting: {e}. Falling back to basic string sort.")
            try:
                sorted_videos_list = sorted(videos_list, key=str)
            except Exception as e_fallback:
                logger.error(f"_get_hashable_videos_representation: ERROR during fallback video list sorting: {e_fallback}. Returning empty tuple.")
                return tuple()
        
        # Apply _make_hashable to each video dictionary/item in the sorted list
        hashable_representation = [self._make_hashable(video_info) for video_info in sorted_videos_list]
        return tuple(hashable_representation)

    @functools.lru_cache(maxsize=256) # Doubled cache size for rendered frames
    def _do_generate_frame_cached(self, frame_index: int, hashable_videos: tuple, total_frames: int, canvas_width: int, canvas_height: int) -> Optional[bytes]:
        """
        Internal method to generate, composite, and encode a frame. This method is cached.
        Canvas dimensions are passed explicitly to be part of the cache key.
        The `hashable_videos` is the deeply hashable representation.
        """
        # Helper to reconstruct the list of dicts from the hashable tuple representation
        def _reconstruct_from_hashable(item):
            if isinstance(item, tuple):
                is_dict_like = True
                if not item:
                    pass
                else:
                    for sub_item in item:
                        if not (isinstance(sub_item, tuple) and len(sub_item) == 2):
                            is_dict_like = False
                            break
                
                if is_dict_like:
                    # Ensure keys are strings if they were originally, common case for JSON-like structures
                    return {str(_reconstruct_from_hashable(k)) if not isinstance(k, (str,int,float,bool,tuple)) else _reconstruct_from_hashable(k) : _reconstruct_from_hashable(v) for k, v in item}
                else:
                    return [_reconstruct_from_hashable(e) for e in item]
            return item

        current_videos = _reconstruct_from_hashable(hashable_videos)

        if not isinstance(current_videos, list):
            logger.warning(f"_do_generate_frame_cached: Reconstructed current_videos is not a list ({type(current_videos)}).")
            if isinstance(current_videos, dict) and hashable_videos and isinstance(hashable_videos[0], tuple): # Heuristic
                 logger.info(f"_do_generate_frame_cached: Attempting to wrap reconstructed dict in a list.")
                 current_videos = [current_videos]

        # If no videos are loaded, return a blank frame
        if not current_videos:
            # Use canvas_width and canvas_height passed as arguments
            return self._create_blank_frame(frame_index, canvas_width, canvas_height)

        # Create a black background frame with current canvas dimensions
        composite_frame = np.zeros((canvas_height, canvas_width, 3), dtype=np.uint8)

        # Flag to check if we actually rendered any videos
        videos_rendered = False

        # Process each video clip in the timeline list
        for video_info in current_videos: # Already converted back from hashable_videos
            video_path = video_info.get('sourcePath') or video_info.get('source_path')
            if not video_path:
                 logger.warning("Skipping clip with no sourcePath in _do_generate_frame_cached")
                 continue

            # Get frame times (using the calculated frames from update_videos if available)
            start_frame_calc = video_info.get('start_frame_calc', 0) # Use calculated frame number
            end_frame_calc = video_info.get('end_frame_calc', total_frames) # Use calculated frame number

            # --- Add detailed logging for frame comparison ---
            logger.debug(f"Checking clip {os.path.basename(video_path)}: timeline_frame={frame_index}, clip_start={start_frame_calc}, clip_end={end_frame_calc}")

            # Exact frame comparison - the frame must be exactly within the clip's range
            if start_frame_calc <= frame_index < end_frame_calc: # Use < for end frame, as frame N is the start of the Nth interval
                # Calculate the frame offset within the source video
                source_start_frame_calc = video_info.get('source_start_frame_calc', 0) # Use calculated frame number
                # Ensure exact frame calculation using calculated frame numbers
                # Offset is how many frames *into* the clip the current timeline frame is
                frame_offset_in_clip = frame_index - start_frame_calc
                source_frame_index = source_start_frame_calc + frame_offset_in_clip

                # --- Add logging for source frame calculation ---
                logger.debug(f"  -> ACTIVE: offset={frame_offset_in_clip}, source_start={source_start_frame_calc}, target_source_frame={source_frame_index}")

                # Get the video capture object
                # Lock is handled within ensure_video_capture if needed, but lru_cache is thread-safe for retrieval.
                # The creation part (_create_video_capture) might need locking if it did more complex things,
                # but VideoCapture creation itself should be okay. The primary concern is FFmpeg operations.
                cap = self.ensure_video_capture(video_path)
                if cap is None:
                    logger.warning(f"Failed to get capture for {video_path}")
                    continue

                # Use lock for FFmpeg operations (set and read)
                # Check if we have this frame in our frame cache
                frame_key = f"{video_path}:{source_frame_index}"
                cached_frame = self._frame_cache.get(frame_key)
                
                if cached_frame is not None:
                    # Use cached frame
                    ret, frame = True, cached_frame
                else:
                    # Improved frame seeking logic
                    with self.video_lock:
                        current_pos = int(cap.get(cv2.CAP_PROP_POS_FRAMES))
                        # Performance optimization for frame seeking
                        if 0 <= source_frame_index - current_pos < 10:
                            # For small forward jumps, sequential reading is faster
                            for _ in range(source_frame_index - current_pos):
                                ret_tmp, _ = cap.read()
                                if not ret_tmp:
                                    break
                            ret, frame = cap.read()
                        elif current_pos > source_frame_index:
                            # For backwards seeking, always use direct seeking
                            cap.set(cv2.CAP_PROP_POS_FRAMES, source_frame_index)
                            ret, frame = cap.read()
                        else:
                            # For larger forward jumps, use key frames
                            cap.set(cv2.CAP_PROP_POS_FRAMES, source_frame_index)
                            ret, frame = cap.read()
                    
                    # Optimized frame caching logic
                    if ret:
                        # Update the LRU cache with size limit
                        if len(self._frame_cache) > 240:  # Double the cache size for better performance
                            # Remove oldest frames more efficiently (last 20%)
                            try:
                                keys_to_remove = list(self._frame_cache.keys())[:48]  # Remove oldest 20%
                                for old_key in keys_to_remove:
                                    del self._frame_cache[old_key]
                            except Exception as e:
                                logger.warning(f"Error managing frame cache: {e}")
                                # Fallback: clear half the cache
                                keys = list(self._frame_cache.keys())
                                for old_key in keys[:len(keys)//2]:
                                    self._frame_cache.pop(old_key, None)
                        
                        # Store frame with zero-copy when possible
                        self._frame_cache[frame_key] = frame

                if not ret:
                    logger.warning(f"Could not read frame {source_frame_index} from {video_path}")
                    continue

                # Process the frame (resize, transform, position)
                processed_frame, x, y, width, height = self._process_frame(frame, video_info)

                # Check if the frame is at least partially within the canvas
                if width <= 0 or height <= 0:
                    logger.warning(f"Invalid frame dimensions: {width}x{height}, skipping")
                    continue

                # Clip the bounds to ensure they fit within the canvas
                visible_x = max(0, x)
                visible_y = max(0, y)
                # Use canvas_width and canvas_height passed as arguments
                visible_width = min(width - (visible_x - x), canvas_width - visible_x)
                visible_height = min(height - (visible_y - y), canvas_height - visible_y)

                # Only attempt to composite if we have some visible portion
                if visible_width > 0 and visible_height > 0:
                    # Calculate source and target areas for the visible portion
                    source_x_offset = visible_x - x
                    source_y_offset = visible_y - y
                    
                    # Ensure these are non-negative for slicing
                    source_slice_x_start = max(0, source_x_offset)
                    source_slice_y_start = max(0, source_y_offset)
                    
                    # Adjust processed_frame slice based on how much is off-canvas
                    processed_frame_slice_x_start = 0 if x >= 0 else -x
                    processed_frame_slice_y_start = 0 if y >= 0 else -y


                    try:
                        # Copy only the visible portion to the composite frame
                        composite_frame[visible_y:visible_y+visible_height, visible_x:visible_x+visible_width] = \
                            processed_frame[processed_frame_slice_y_start:processed_frame_slice_y_start+visible_height, 
                                            processed_frame_slice_x_start:processed_frame_slice_x_start+visible_width]
                        videos_rendered = True
                    except IndexError as e:
                         logger.error(f"IndexError during compositing: {e}. Comp: {visible_y}:{visible_y+visible_height}, {visible_x}:{visible_x+visible_width}. Proc: {processed_frame_slice_y_start}:{processed_frame_slice_y_start+visible_height}, {processed_frame_slice_x_start}:{processed_frame_slice_x_start+visible_width}. Frame shape: {processed_frame.shape}")
                    except Exception as e:
                        logger.error(f"Error compositing frame: {e}, dims={visible_x},{visible_y},{visible_width},{visible_height}")
                else:
                    logger.warning(f"Frame entirely outside bounds: {x},{y},{width},{height}")

        # Add debug frame number to all frames
        cv2.putText(
            composite_frame,
            f"Frame: {frame_index}",
            (10, 30),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (200, 200, 200),
            1
        )

        # If no videos were rendered despite having entries, show a message
        if not videos_rendered and current_videos:
            self._add_no_visible_clips_message(composite_frame, frame_index)

        # Optimized frame encoding
        # Use lock for encoding to prevent FFmpeg threading issues
        with self.video_lock:
            # Use faster encoding parameters
            encode_params = [
                int(cv2.IMWRITE_JPEG_QUALITY), self.jpeg_quality,
                int(cv2.IMWRITE_JPEG_OPTIMIZE), 1,
                int(cv2.IMWRITE_JPEG_PROGRESSIVE), 0  # Turn off progressive encoding for speed
            ]
            success, buffer = cv2.imencode('.jpg', composite_frame, encode_params)
        
        if success:
            return buffer.tobytes()
        else:
            logger.error(f"Failed to encode frame {frame_index} to JPEG.")
            return None

    def get_frame(self, frame_index: int, current_videos: List[Dict], total_frames: int) -> Optional[bytes]:
        """
        Get a composite frame at the specified index.
        This method now calls the cached internal generation method.
        """
        hashable_videos_rep = self._get_hashable_videos_representation(current_videos)
        # Pass current canvas dimensions to the cached method
        return self._do_generate_frame_cached(
            frame_index,
            hashable_videos_rep,
            total_frames,
            self.canvas_width, # Pass current canvas width
            self.canvas_height # Pass current canvas height
        )

    def _process_frame(self, frame, video_info): # canvas_width and canvas_height are instance variables self.canvas_width, self.canvas_height
        """Process a frame based on video_info metadata (resize, flip, etc.)"""
        # Resize and position the frame according to previewRect from metadata
        metadata = video_info.get('metadata', {})
        preview_rect_data = metadata.get('previewRect') # Get the previewRect dictionary

        # Define default rect values using current canvas dimensions
        frame_height_orig, frame_width_orig = frame.shape[:2]  # Get original frame dimensions

        # Calculate default width and height to fit within canvas while maintaining aspect ratio
        if frame_width_orig == 0 or frame_height_orig == 0 : # Avoid division by zero
            default_width = self.canvas_width
            default_height = self.canvas_height
        elif frame_width_orig > self.canvas_width or frame_height_orig > self.canvas_height:
            # Scale down to fit canvas
            width_ratio = self.canvas_width / frame_width_orig
            height_ratio = self.canvas_height / frame_height_orig
            scale_ratio = min(width_ratio, height_ratio)
            default_width = int(frame_width_orig * scale_ratio)
            default_height = int(frame_height_orig * scale_ratio)
        else:
            # Use original dimensions
            default_width = frame_width_orig
            default_height = frame_height_orig

        # Center the frame on canvas
        default_left = (self.canvas_width - default_width) / 2
        default_top = (self.canvas_height - default_height) / 2

        default_rect = {
            'left': default_left,
            'top': default_top,
            'width': float(default_width),
            'height': float(default_height)
        }

        if isinstance(preview_rect_data, dict):
            # Use values from previewRect_data, falling back to defaults if keys are missing
            x = int(preview_rect_data.get('left', default_rect['left']))
            y = int(preview_rect_data.get('top', default_rect['top']))
            # Ensure width/height are positive, default to reasonable values if not
            width = max(1, int(preview_rect_data.get('width', default_rect['width'])))
            height = max(1, int(preview_rect_data.get('height', default_rect['height'])))
            logger.debug(f"Using previewRect from metadata: x={x}, y={y}, w={width}, h={height}")
        else:
            # Use all default values if previewRect is missing or not a dict
            x = int(default_rect['left'])
            y = int(default_rect['top'])
            width = int(default_rect['width'])
            height = int(default_rect['height'])
            logger.debug(f"Using default previewRect (centered): x={x}, y={y}, w={width}, h={height}")
        
        # Ensure width and height for resize are at least 1
        resize_width = max(1, width)
        resize_height = max(1, height)

        # Resize the frame
        try:
            if frame_width_orig > 0 and frame_height_orig > 0: # only resize if frame is valid
                # Skip resize if dimensions are very close (within 5%)
                if abs(frame_width_orig - resize_width) < frame_width_orig * 0.05 and abs(frame_height_orig - resize_height) < frame_height_orig * 0.05:
                    resized_frame = frame  # Use original to avoid resize overhead
                else:
                    # Use fastest interpolation method for resizing
                    resized_frame = cv2.resize(frame, (resize_width, resize_height),
                                            interpolation=self.resize_interpolation)
            else:
                resized_frame = frame # return original if it's invalid
                logger.warning(f"Original frame has zero dimension: {frame_width_orig}x{frame_height_orig}. Skipping resize.")

        except cv2.error as e:
            logger.error(f"OpenCV Error resizing frame to {resize_width}x{resize_height}: {e}. Original: {frame_width_orig}x{frame_height_orig}")
            # Fallback: return original frame and original dimensions as rect
            return frame, int(default_rect['left']), int(default_rect['top']), frame_width_orig, frame_height_orig
        except Exception as e:
            logger.error(f"Error resizing frame to {resize_width}x{resize_height}: {e}")
            # Fallback: return original frame and original dimensions as rect
            return frame, int(default_rect['left']), int(default_rect['top']), frame_width_orig, frame_height_orig

        # Flip the frame vertically if specified in metadata
        flip = video_info.get('flip', False) # Assuming 'flip' means vertical flip
        if flip:
            resized_frame = cv2.flip(resized_frame, 0)  # 0 for vertical flip

        return resized_frame, x, y, width, height # Return the calculated x,y,width,height for positioning

    def _create_blank_frame(self, frame_index: int, canvas_width: int, canvas_height: int) -> Optional[bytes]:
        """
        Create a blank black frame with the given canvas dimensions.
        Dimensions are passed to ensure consistency with the caller's expectations.
        """
        frame = np.zeros((canvas_height, canvas_width, 3), dtype=np.uint8)
        text = f"No videos loaded (Frame: {frame_index})"
        # Calculate text size to center it
        (text_width, text_height), _ = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, 1, 2)
        text_x = (canvas_width - text_width) // 2
        text_y = (canvas_height + text_height) // 2
        
        cv2.putText(
            frame,
            text,
            (text_x, text_y),
            cv2.FONT_HERSHEY_SIMPLEX,
            1,
            (200, 200, 200),
            2
        )
        with self.video_lock: # Ensure thread safety for imencode
            jpeg_quality = [int(cv2.IMWRITE_JPEG_QUALITY), self.jpeg_quality]
            success, buffer = cv2.imencode('.jpg', frame, jpeg_quality)
        
        if success:
            return buffer.tobytes()
        else:
            logger.error(f"Failed to encode blank frame {frame_index} to JPEG.")
            return None

    def _add_no_visible_clips_message(self, frame, frame_index): # Uses self.canvas_width/height
        """Add a message to the frame indicating that no clips are visible."""
        text = f"No visible clips (Frame: {frame_index})"
        # Calculate text size to center it
        (text_width, text_height), _ = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, 1, 2)
        text_x = (self.canvas_width - text_width) // 2 # Uses current instance canvas dimensions
        text_y = (self.canvas_height + text_height) // 2 # Uses current instance canvas dimensions
        cv2.putText(
            frame,
            text,
            (text_x, text_y), # Centered
            cv2.FONT_HERSHEY_SIMPLEX,
            1, # Font scale
            (200, 200, 200), # Color
            2 # Thickness
        )

    @functools.lru_cache(maxsize=64)  # Increased cache for VideoCapture objects
    def _create_video_capture(self, video_path: str) -> Optional[cv2.VideoCapture]:
        """Create a video capture object for the given path. This is cached."""
        logger.debug(f"Attempting to create VideoCapture for: {video_path}")
        if not os.path.exists(video_path):
            logger.error(f"Video file not found: {video_path}")
            return None

        try:
            # Critical section for VideoCapture creation if it's not thread-safe
            # However, typical VideoCapture creation itself is often okay,
            # the issues arise with subsequent operations like read/set.
            # The RLock in ensure_video_capture protects the critical get/set/read operations.
            # Add optimization flags to VideoCapture
            cap = cv2.VideoCapture(video_path, cv2.CAP_FFMPEG)
            # Set buffer size for better performance
            cap.set(cv2.CAP_PROP_BUFFERSIZE, 3)
            if not cap.isOpened():
                logger.error(f"Could not open video: {video_path}")
                return None
            logger.info(f"Successfully opened video and cached: {video_path}")
            return cap
        except Exception as e:
            logger.error(f"Exception creating VideoCapture for {video_path}: {e}")
            return None


    def ensure_video_capture(self, video_path: str) -> Optional[cv2.VideoCapture]:
        """
        Ensure a video capture object exists for the given path using LRU cache.
        The lock here is primarily for operations on the VideoCapture object (set, read),
        as _create_video_capture is memoized by lru_cache.
        """
        # _create_video_capture is cached, so it's fast after the first call.
        # The lock is around _create_video_capture if its internals were complex and not thread-safe.
        # For basic VideoCapture, this might be overkill, but better safe.
        # More importantly, the lock is used in get_frame for cap.set/read.
        return self._create_video_capture(video_path)


    def cleanup(self):
        """Release all video capture objects by clearing the LRU cache and frame cache."""
        logger.info("Cleaning up FrameGenerator: Clearing VideoCapture and pre-rendered frame caches.")
        with self.video_lock: # Protect cache clearing if other operations might access concurrently
            self._create_video_capture.cache_clear()
            self._do_generate_frame_cached.cache_clear()
        logger.info("VideoCapture and pre-rendered frame caches cleared.")
        
        # Also clear the frame cache
        self._frame_cache.clear()

    def clear_all_caches(self):
        """Explicit method to clear all caches, might be called from preview_server if timeline changes significantly."""
        logger.info("Clearing all FrameGenerator caches (VideoCapture and pre-rendered frames).")
        with self.video_lock:
            self._create_video_capture.cache_clear()
            self._do_generate_frame_cached.cache_clear()
            # Clear the frame cache as well
            self._frame_cache.clear()
        logger.info("All FrameGenerator caches cleared.")