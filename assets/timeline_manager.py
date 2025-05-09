#!/usr/bin/env python3
import logging
import os
from typing import Dict, List, Optional

import config
import db_access

logger = logging.getLogger('video_stream_server')

class TimelineManager:
    def __init__(self):
        # Timeline state
        self.current_videos: List[Dict] = []
        self.frame_rate = config.DEFAULT_FRAME_RATE
        self.total_frames = config.DEFAULT_TOTAL_FRAMES
        self.db_manager = db_access.get_manager()
        
        # Auto-connect to the most recent project database
        if self.db_manager.connect_to_project():
            self.refresh_from_database()
    
    def refresh_from_database(self):
        """Load clips data directly from the connected project database"""
        logger.info("Refreshing timeline data from database")
        
        # Check if database connection is active, try to reconnect if not
        if not self.db_manager.project_session:
            logger.warning("Database connection not active, attempting to reconnect...")
            
            # Try to connect to the most recent project
            if not self.db_manager.connect_to_project():
                logger.error("Failed to reconnect to database")
                # Keep existing clips rather than clearing them on connection failure
                return
            
            logger.info("Successfully reconnected to database")
        
        # Get all clips from the database
        try:
            clips = self.db_manager.get_all_clips()
            
            if not clips:
                logger.info("No clips found in database")
                # Only clear videos if we successfully connected but found no clips
                self.current_videos = []
                self.total_frames = config.DEFAULT_TOTAL_FRAMES
                return
                
            # Use update_videos with database clips
            self.update_videos(clips)
            
            logger.info(f"Timeline refreshed from database: {len(self.current_videos)} clips loaded")
            
        except Exception as e:
            logger.error(f"Error refreshing timeline from database: {e}")
            # Keep existing timeline state on error
    
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

            # Use 'sourcePath' or 'source_path' depending on the source of data
            path = video.get('sourcePath') or video.get('source_path')
            if not path:
                logger.warning(f"Skipped video [{index}] with missing source path")
                continue
                
            if not os.path.exists(path):
                logger.warning(f"Video file not found: {path}")
                continue
                
            # Fetch millisecond times needed for calculation first
            # Support both camelCase (from WebSocket) and snake_case (from DB) formats
            start_frame_ms = video.get('startTimeOnTrackMs') or video.get('start_time_on_track_ms', 0)
            end_frame_ms = video.get('endTimeOnTrackMs') or video.get('end_time_on_track_ms', 0)
            source_start_ms = video.get('startTimeInSourceMs') or video.get('start_time_in_source_ms', 0)

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
            # Use calculated frame numbers for logging
            start_frame = video['start_frame_calc']
            end_frame = video['end_frame_calc']
            source_start_frame = video['source_start_frame_calc']

            # Get new transform properties, preferring camelCase (from db_access.to_dict) then snake_case as fallback
            pos_x = video.get('previewPositionX') # or video.get('preview_position_x')
            pos_y = video.get('previewPositionY') # or video.get('preview_position_y')
            width = video.get('previewWidth')     # or video.get('preview_width')
            height = video.get('previewHeight')   # or video.get('preview_height')

            # Construct pos_info using new direct properties
            # Ensure they are not None before formatting, provide defaults '?' if missing
            pos_x_str = f"{pos_x:.2f}" if pos_x is not None else "?"
            pos_y_str = f"{pos_y:.2f}" if pos_y is not None else "?"
            width_str = f"{width:.2f}" if width is not None else "?"
            height_str = f"{height:.2f}" if height is not None else "?"
            
            pos_info = f"pos:({pos_x_str},{pos_y_str}) size:({width_str},{height_str})"
            
            time_info = f"frames: {start_frame}-{end_frame} (src_start: {source_start_frame})"
            logger.info(f"Added video [{index}]: {os.path.basename(path)}, {pos_info}, {time_info} (calc)")
                
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
    
    def handle_message_updates(self, video_data: List[Dict]):
        """Handle updates from WebSocket messages (legacy method)"""
        logger.info("Received clip update message from Flutter app")
        self.update_videos(video_data)
    
    def get_timeline_state(self):
        """Get the current timeline state as a dictionary"""
        return {
            "videos": self.current_videos,
            "frame_rate": self.frame_rate,
            "total_frames": self.total_frames
        }