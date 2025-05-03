#!/usr/bin/env python3
import logging
import os
from typing import Dict, List, Optional

import config

logger = logging.getLogger('video_stream_server')

class TimelineManager:
    def __init__(self):
        # Timeline state
        self.current_videos: List[Dict] = []
        self.frame_rate = config.DEFAULT_FRAME_RATE
        self.total_frames = config.DEFAULT_TOTAL_FRAMES
    
    def update_videos(self, video_data: List[Dict]):
        """Update the list of videos in the timeline."""
        # Clear old videos list
        old_video_count = len(self.current_videos)
        self.current_videos.clear()
        logger.debug(f"Cleared {old_video_count} old video entries.")
        
        if not video_data:
            logger.info("Received empty video data - clearing all videos")
            self.total_frames = config.DEFAULT_TOTAL_FRAMES  # Reset to default when clearing
            return
            
        logger.info(f"Updating videos: received {len(video_data)} videos for timeline")
        
        # Add new videos
        video_count = 0
        for index, video in enumerate(video_data):
            # Log the raw dictionary for the first few videos
            if index < 3:
                 logger.debug(f"Processing video data [{index}]: {video}")

            # Use 'sourcePath' instead of 'path'
            path = video.get('sourcePath')
            if not path:
                logger.warning(f"Skipped video [{index}] with missing sourcePath")
                continue
                
            if not os.path.exists(path):
                logger.warning(f"Video file not found: {path}")
                continue
                
            # Fetch millisecond times needed for calculation first
            start_frame_ms = video.get('startTimeOnTrackMs', 0)
            end_frame_ms = video.get('endTimeOnTrackMs', 0)
            source_start_ms = video.get('startTimeInSourceMs', 0)

            # Calculate frame numbers here and store them in the dictionary
            # --- Use self.frame_rate consistently ---
            fps = self.frame_rate
            if fps <= 0:
                logger.warning(f"Invalid frame rate ({fps}) detected. Defaulting to 30 for calculations.")
                fps = 30 # Fallback to default if frame rate is invalid

            video['start_frame_calc'] = int(start_frame_ms * fps / 1000)
            # Use '<' comparison logic for end frame, so calculate end frame exclusive
            video['end_frame_calc'] = int(end_frame_ms * fps / 1000)
            video['source_start_frame_calc'] = int(source_start_ms * fps / 1000)

            # --- Log calculated frames ---
            logger.debug(f"  Clip {index}: ms(track={start_frame_ms}-{end_frame_ms}, src_start={source_start_ms}) -> frames(track={video['start_frame_calc']}-{video['end_frame_calc']}, src_start={video['source_start_frame_calc']}) @ {fps}fps")

            # Append the video configuration dictionary to the list
            self.current_videos.append(video)
            video_count += 1
            
            # Log some basic info about the video using calculated frames
            metadata = video.get('metadata', {}) # Get metadata for previewRect access
            preview_rect_data = metadata.get('previewRect', {}) # Get previewRect safely
            
            # Use calculated frame numbers for logging
            start_frame = video['start_frame_calc']
            end_frame = video['end_frame_calc']
            source_start_frame = video['source_start_frame_calc']

            # Add the frame conversion info to the log
            # Use preview_rect_data safely for position info
            pos_info = f"pos: {preview_rect_data.get('left', '?')},{preview_rect_data.get('top', '?')}"
            time_info = f"frames: {start_frame}-{end_frame} (src_start: {source_start_frame})" # Already calculated frames
            logger.info(f"Added video [{index}]: {os.path.basename(path)}, {pos_info}, {time_info} (calc)") # Indicate calculated frames
                
            # Update frame rate and total frames if needed
            if 'frame_rate' in video:
                self.frame_rate = video['frame_rate']
                logger.debug(f"Updated frame rate to {self.frame_rate}")
                
            # Update total_frames based on endTimeOnTrackMs
            if end_frame_ms > 0: # Check if endTimeOnTrackMs is valid
                 # Convert end_frame_ms to frames for total_frames calculation
                 # Use the calculated end_frame_calc for total_frames
                 self.total_frames = max(self.total_frames, video['end_frame_calc'])
                 logger.debug(f"Updated total frames to {self.total_frames} based on clip end frame {video['end_frame_calc']}")
            else:
                 logger.warning(f"Video [{index}] has invalid endTimeOnTrackMs: {end_frame_ms}")
                    
        logger.info(f"Timeline updated: {video_count} valid videos added")
        
        # If we have no videos after processing, set the default empty state
        if not self.current_videos:
            logger.warning("No valid videos found in the data")
            self.total_frames = config.DEFAULT_TOTAL_FRAMES  # Reset to default
    
    def get_timeline_state(self):
        """Get the current timeline state as a dictionary"""
        return {
            "videos": self.current_videos,
            "frame_rate": self.frame_rate,
            "total_frames": self.total_frames
        }