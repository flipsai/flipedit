#!/usr/bin/env python3
import cv2
import os
import logging

logger = logging.getLogger('video_stream_server')

def get_media_duration(file_path):
    """Get the duration of a media file in milliseconds using OpenCV."""
    try:
        if not os.path.exists(file_path):
            logger.error(f"File does not exist: {file_path}")
            return 0
            
        cap = cv2.VideoCapture(file_path)
        if not cap.isOpened():
            logger.error(f"Failed to open file with OpenCV: {file_path}")
            return 0
            
        # Get frame count and fps
        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        fps = cap.get(cv2.CAP_PROP_FPS)
        
        # Calculate duration in milliseconds
        if fps > 0:
            duration_ms = int((frame_count / fps) * 1000)
        else:
            logger.warning(f"Invalid FPS ({fps}) for {file_path}, using frame count as duration")
            duration_ms = frame_count * 33  # Assume ~30fps (33ms per frame)
        
        # Release the capture when done
        cap.release()
        
        logger.info(f"Media duration for {os.path.basename(file_path)}: {duration_ms}ms ({frame_count} frames at {fps} fps)")
        return duration_ms
    except Exception as e:
        logger.error(f"Error getting media duration: {e}")
        return 0

def get_media_info(file_path):
    """Get both duration and dimensions of a media file using OpenCV."""
    try:
        if not os.path.exists(file_path):
            logger.error(f"File does not exist: {file_path}")
            return {"duration_ms": 0, "width": 0, "height": 0}
            
        cap = cv2.VideoCapture(file_path)
        if not cap.isOpened():
            logger.error(f"Failed to open file with OpenCV: {file_path}")
            return {"duration_ms": 0, "width": 0, "height": 0}
            
        # Get frame count and fps for duration
        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        fps = cap.get(cv2.CAP_PROP_FPS)
        
        # Get dimensions
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        
        # Calculate duration in milliseconds
        if fps > 0:
            duration_ms = int((frame_count / fps) * 1000)
        else:
            logger.warning(f"Invalid FPS ({fps}) for {file_path}, using frame count as duration")
            duration_ms = frame_count * 33  # Assume ~30fps (33ms per frame)
        
        # Read first frame for image files (which may report 0 for frame count and fps)
        if frame_count == 0 and fps == 0:
            ret, frame = cap.read()
            if ret and frame is not None:
                height, width = frame.shape[:2]
                # For images, set a default duration
                duration_ms = 5000  # 5 seconds
        
        # Release the capture when done
        cap.release()
        
        logger.info(f"Media info for {os.path.basename(file_path)}: {width}x{height}, {duration_ms}ms")
        return {
            "duration_ms": duration_ms,
            "width": width,
            "height": height
        }
    except Exception as e:
        logger.error(f"Error getting media info: {e}")
        return {"duration_ms": 0, "width": 0, "height": 0}