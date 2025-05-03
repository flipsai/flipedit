#!/usr/bin/env python3
import asyncio
import base64
import logging
from typing import Callable, Optional

logger = logging.getLogger('video_stream_server')

class PlaybackController:
    def __init__(self, frame_getter_callback: Callable, send_frame_callback: Callable):
        """
        Initialize the playback controller
        
        Args:
            frame_getter_callback: Function that returns a frame for a given index
            send_frame_callback: Function that sends a frame to clients
        """
        self.is_playing = False
        self.current_frame = 0
        self.total_frames = 600  # Default, will be updated by TimelineManager
        self.frame_rate = 30  # Default, will be updated by TimelineManager
        
        # Store callback functions
        self.get_frame = frame_getter_callback
        self.send_frame_to_all = send_frame_callback
        
        # Playback control
        self.play_task = None
        self.shutdown_event = asyncio.Event()
    
    def set_timeline_params(self, frame_rate: float, total_frames: int):
        """Update playback parameters from timeline"""
        self.frame_rate = frame_rate
        self.total_frames = total_frames
        logger.debug(f"Updated playback parameters: {frame_rate} fps, {total_frames} total frames")
    
    def seek(self, frame: int) -> int:
        """
        Seek to a specific frame
        
        Args:
            frame: The frame to seek to
            
        Returns:
            The actual frame that was seeked to (may be clamped to valid range)
        """
        old_frame = self.current_frame
        self.current_frame = max(0, min(frame, self.total_frames - 1))
        
        # Log frame changes for debugging timing issues
        if abs(old_frame - self.current_frame) > 1 or frame % 30 == 0:
            logger.info(f"Seek request: {frame}, actual: {self.current_frame}")
            
        return self.current_frame
    
    async def start_playback(self):
        """Start the playback loop."""
        if self.play_task is not None and not self.play_task.done():
            logger.warning("Playback already running")
            return
            
        self.is_playing = True
        self.play_task = asyncio.create_task(self.playback_loop())
        logger.info("Started playback")

    async def stop_playback(self):
        """Stop the playback loop."""
        self.is_playing = False
        if self.play_task is not None and not self.play_task.done():
            # Wait for playback loop to finish
            await self.play_task
        self.play_task = None
        logger.info("Stopped playback")

    async def playback_loop(self):
        """Main playback loop that sends frames at the appropriate frame rate."""
        frame_time = 1.0 / self.frame_rate  # Time per frame in seconds
        
        try:
            while self.is_playing and not self.shutdown_event.is_set():
                start_time = asyncio.get_event_loop().time()
                
                # Get the current frame
                frame_bytes = self.get_frame(self.current_frame)
                if frame_bytes:
                    # Convert to base64 and send to clients
                    encoded_frame = base64.b64encode(frame_bytes).decode('utf-8')
                    await self.send_frame_to_all(encoded_frame)
                
                # Increment frame counter
                self.current_frame += 1
                if self.current_frame >= self.total_frames:
                    self.current_frame = 0  # Loop back to start
                
                # Calculate time to sleep to maintain frame rate
                elapsed = asyncio.get_event_loop().time() - start_time
                sleep_time = max(0, frame_time - elapsed)
                
                # Sleep until next frame time
                await asyncio.sleep(sleep_time)
        except Exception as e:
            logger.error(f"Playback loop error: {e}")
            self.is_playing = False
    
    def get_playback_state(self):
        """Get the current playback state as a dictionary"""
        return {
            "playing": self.is_playing,
            "current_frame": self.current_frame
        }
    
    def shutdown(self):
        """Signal shutdown to stop any playback loops"""
        self.shutdown_event.set()