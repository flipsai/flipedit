#!/usr/bin/env python3
import cv2
import os
import logging
import functools
import threading
from typing import Optional, Tuple
import numpy as np

logger = logging.getLogger(__name__)

class VideoSourceService:
    """
    Service responsible for loading video files, managing VideoCapture objects,
    and providing raw frames.
    """
    def __init__(self, max_cache_size: int = 32):
        # Thread safety for FFmpeg operations on VideoCapture objects
        self.video_lock = threading.RLock()
        # Configure the LRU cache size for VideoCapture objects
        # self._create_video_capture_cached.cache_configure(maxsize=max_cache_size) # REMOVED: This caused AttributeError. Maxsize is set in decorator.
        logger.info(f"VideoSourceService initialized with cache size {max_cache_size}") # Note: max_cache_size param is now illustrative for this cache.

    @functools.lru_cache(maxsize=32) # MODIFIED: Set maxsize directly here, using default from __init__
    def _create_video_capture_cached(self, video_path: str) -> Optional[cv2.VideoCapture]:
        """
        Creates and caches a VideoCapture object for the given path.
        This method is memoized using lru_cache.
        """
        logger.debug(f"Attempting to create VideoCapture for: {video_path}")
        if not os.path.exists(video_path):
            logger.error(f"Video file not found: {video_path}")
            return None

        try:
            # Add optimization flags to VideoCapture
            cap = cv2.VideoCapture(video_path, cv2.CAP_FFMPEG)
            # Set buffer size for better performance (can be tuned)
            cap.set(cv2.CAP_PROP_BUFFERSIZE, 3)
            if not cap.isOpened():
                logger.error(f"Could not open video: {video_path}")
                return None
            logger.info(f"Successfully opened video and cached: {video_path}")
            return cap
        except Exception as e:
            logger.error(f"Exception creating VideoCapture for {video_path}: {e}")
            return None

    def get_video_capture(self, video_path: str) -> Optional[cv2.VideoCapture]:
        """
        Retrieves a VideoCapture object for the given path, utilizing the cache.
        """
        return self._create_video_capture_cached(video_path)

    def get_frame(self, video_path: str, frame_index: int) -> Optional[np.ndarray]:
        """
        Retrieves a specific frame from the video file.

        Args:
            video_path: Path to the video file.
            frame_index: The 0-based index of the frame to retrieve.

        Returns:
            The frame as a NumPy array if successful, None otherwise.
        """
        cap = self.get_video_capture(video_path)
        if cap is None:
            logger.warning(f"Failed to get capture for {video_path} to retrieve frame {frame_index}")
            return None

        with self.video_lock: # Ensure thread-safe operations on the VideoCapture object
            try:
                # Get total frames to validate frame_index
                total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
                if not (0 <= frame_index < total_frames):
                    logger.warning(f"Frame index {frame_index} is out of bounds for {video_path} (Total: {total_frames}).")
                    # Attempt to read frame 0 as a fallback or handle as error
                    # For now, let's try to set and read, OpenCV might handle it or return error
                    # return None 
                
                current_pos = int(cap.get(cv2.CAP_PROP_POS_FRAMES))
                
                # Optimized frame seeking logic (similar to original FrameGenerator)
                if current_pos == frame_index + 1: # Already at the desired frame if read was just done
                    ret, frame = cap.read() # This might be problematic if we just set it
                                            # Let's always set then read for simplicity here,
                                            # can optimize later if this becomes a bottleneck.

                # Always set position before reading for a specific frame_index
                cap.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
                ret, frame = cap.read()

                if not ret:
                    logger.warning(f"Could not read frame {frame_index} from {video_path}. Current pos: {cap.get(cv2.CAP_PROP_POS_FRAMES)}")
                    return None
                return frame
            except Exception as e:
                logger.error(f"Error reading frame {frame_index} from {video_path}: {e}")
                return None
    
    def get_video_properties(self, video_path: str) -> Optional[dict]:
        """
        Retrieves properties of the video like fps, frame count, width, height.
        """
        cap = self.get_video_capture(video_path)
        if cap is None:
            logger.warning(f"Failed to get capture for {video_path} to retrieve properties.")
            return None
        
        with self.video_lock:
            try:
                fps = cap.get(cv2.CAP_PROP_FPS)
                frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
                width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
                height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
                return {
                    "fps": fps,
                    "frame_count": frame_count,
                    "width": width,
                    "height": height,
                    "duration_ms": (frame_count / fps) * 1000 if fps > 0 else 0
                }
            except Exception as e:
                logger.error(f"Error getting properties for {video_path}: {e}")
                return None

    def clear_cache(self):
        """Releases all cached VideoCapture objects."""
        logger.info("Clearing VideoSourceService cache (VideoCapture objects).")
        self._create_video_capture_cached.cache_clear()

    def __del__(self):
        """Ensure caches are cleared when the service instance is deleted."""
        self.clear_cache()
        logger.info("VideoSourceService instance deleted and cache cleared.")

if __name__ == '__main__':
    # Example Usage (for testing)
    logging.basicConfig(level=logging.DEBUG)
    # Create a dummy video file for testing
    dummy_video_path = "dummy_test_video.mp4"
    if not os.path.exists(dummy_video_path):
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        out = cv2.VideoWriter(dummy_video_path, fourcc, 30.0, (100, 100))
        for i in range(90): # 3 seconds of video
            frame = np.zeros((100, 100, 3), dtype=np.uint8)
            cv2.putText(frame, str(i), (10, 50), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
            out.write(frame)
        out.release()
        logger.info(f"Created dummy video: {dummy_video_path}")

    source_service = VideoSourceService(max_cache_size=2)

    # Test getting properties
    props = source_service.get_video_properties(dummy_video_path)
    if props:
        logger.info(f"Properties for {dummy_video_path}: {props}")
    
    # Test getting a frame
    test_frame_index = 10
    frame = source_service.get_frame(dummy_video_path, test_frame_index)
    if frame is not None:
        logger.info(f"Successfully retrieved frame {test_frame_index} from {dummy_video_path}. Shape: {frame.shape}")
        # cv2.imshow(f"Frame {test_frame_index}", frame)
        # cv2.waitKey(0)
        # cv2.destroyAllWindows()
    else:
        logger.error(f"Failed to retrieve frame {test_frame_index} from {dummy_video_path}")

    # Test caching (try getting the same video again)
    logger.info("Requesting same video again to test caching...")
    frame_again = source_service.get_frame(dummy_video_path, test_frame_index + 1)
    if frame_again is not None:
        logger.info(f"Successfully retrieved frame {test_frame_index + 1} again (cache test).")

    # Test with a non-existent file
    logger.info("Requesting non-existent video...")
    non_existent_frame = source_service.get_frame("non_existent_video.mp4", 0)
    if non_existent_frame is None:
        logger.info("Correctly failed to get frame from non-existent video.")

    # Clean up dummy video
    # if os.path.exists(dummy_video_path):
    #     os.remove(dummy_video_path)
    #     logger.info(f"Removed dummy video: {dummy_video_path}")
    
    source_service.clear_cache()
    logger.info("Test complete.")