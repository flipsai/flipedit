#!/usr/bin/env python3
import cv2
import numpy as np
import os
import logging
from typing import Dict, List, Optional

logger = logging.getLogger('video_stream_server')

class FrameGenerator:
    def __init__(self):
        # Video cache to reuse video capture objects
        self.video_cache: Dict[str, cv2.VideoCapture] = {}
    
    def get_frame(self, frame_index: int, current_videos: List[Dict], total_frames: int) -> Optional[bytes]:
        """Get a composite frame at the specified index."""
        # If no videos are loaded, return a blank frame
        if not current_videos:
            return self._create_blank_frame(frame_index)
        
        # Create a black background frame
        composite_frame = np.zeros((720, 1280, 3), dtype=np.uint8)
        
        # Flag to check if we actually rendered any videos
        videos_rendered = False
        
        # Process each video clip in the timeline list
        for video_info in current_videos:
            video_path = video_info.get('sourcePath')
            if not video_path:
                 logger.warning("Skipping clip with no sourcePath in get_frame")
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
                cap = self.ensure_video_capture(video_path)
                if cap is None:
                    logger.warning(f"Failed to get capture for {video_path}")
                    continue
                    
                # Set the position in the video
                cap.set(cv2.CAP_PROP_POS_FRAMES, source_frame_index)
                
                # Read the frame
                ret, frame = cap.read()
                if not ret:
                    logger.warning(f"Could not read frame {source_frame_index} from {video_path}")
                    continue
                
                # Process the frame (resize, transform, position)
                processed_frame, x, y, width, height = self._process_frame(frame, video_info)
                
                # Check if the area is within the composite frame
                if (x >= 0 and y >= 0 and 
                    x + width <= composite_frame.shape[1] and 
                    y + height <= composite_frame.shape[0]):
                    
                    # Place the frame on the composite image
                    composite_frame[y:y+height, x:x+width] = processed_frame
                    videos_rendered = True
                else:
                    logger.warning(f"Frame position outside bounds: {x},{y},{width},{height}")
        
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
        
        # Encode the composite frame
        _, buffer = cv2.imencode('.jpg', composite_frame)
        return buffer.tobytes()

    def _process_frame(self, frame, video_info):
        """Process a frame based on video_info metadata (resize, flip, etc.)"""
        # Resize and position the frame according to previewRect from metadata
        metadata = video_info.get('metadata', {})
        preview_rect_data = metadata.get('previewRect') # Get the previewRect dictionary

        # Define default rect values
        default_rect = {'left': 0.0, 'top': 0.0, 'width': 1280.0, 'height': 720.0} # Default to full frame

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
             logger.debug("Using default previewRect (metadata missing or invalid)")
        
        # Resize the frame
        resized_frame = cv2.resize(frame, (width, height))
        
        # Apply flip if needed (using previewFlip from metadata)
        flip_int = metadata.get('previewFlip', 0) # Default to 0 (no flip)
        if flip_int == 1:  # Horizontal
            resized_frame = cv2.flip(resized_frame, 1)
            logger.debug("Applied horizontal flip")
        elif flip_int == 2:  # Vertical
            resized_frame = cv2.flip(resized_frame, 0)
            logger.debug("Applied vertical flip")
        
        return resized_frame, x, y, width, height

    def _create_blank_frame(self, frame_index):
        """Create a blank frame with instructional text"""
        # Create a black frame
        blank_frame = np.zeros((720, 1280, 3), dtype=np.uint8)
        
        # Add text to the frame
        cv2.putText(
            blank_frame, 
            "No videos in timeline", 
            (480, 360), 
            cv2.FONT_HERSHEY_SIMPLEX, 
            1, 
            (255, 255, 255), 
            2
        )
        
        # Add smaller instruction text
        cv2.putText(
            blank_frame, 
            "Drag media to timeline to add clips", 
            (450, 400), 
            cv2.FONT_HERSHEY_SIMPLEX, 
            0.7, 
            (200, 200, 200), 
            1
        )
        
        # Add debug frame number
        cv2.putText(
            blank_frame, 
            f"Frame: {frame_index}", 
            (10, 30), 
            cv2.FONT_HERSHEY_SIMPLEX, 
            0.5, 
            (200, 200, 200), 
            1
        )
        
        _, buffer = cv2.imencode('.jpg', blank_frame)
        return buffer.tobytes()

    def _add_no_visible_clips_message(self, frame, frame_index):
        """Add message indicating that no clips are visible at current frame"""
        # Add text explaining the issue
        cv2.putText(
            frame, 
            "No clips visible at current frame", 
            (400, 360), 
            cv2.FONT_HERSHEY_SIMPLEX, 
            1, 
            (255, 255, 255), 
            2
        )
        cv2.putText(
            frame, 
            f"Current frame: {frame_index}", 
            (500, 400), 
            cv2.FONT_HERSHEY_SIMPLEX, 
            0.7, 
            (200, 200, 200), 
            1
        )

    def ensure_video_capture(self, video_path: str) -> Optional[cv2.VideoCapture]:
        """Ensure a video capture object exists for the given path."""
        if video_path not in self.video_cache:
            if not os.path.exists(video_path):
                logger.error(f"Video file not found: {video_path}")
                return None
                
            cap = cv2.VideoCapture(video_path)
            if not cap.isOpened():
                logger.error(f"Could not open video: {video_path}")
                return None
                
            self.video_cache[video_path] = cap
            
        return self.video_cache[video_path]

    def cleanup(self):
        """Release all video capture objects"""
        for cap in self.video_cache.values():
            cap.release()
        self.video_cache.clear()