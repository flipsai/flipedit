#!/usr/bin/env python3
import asyncio
import websockets
import cv2
import numpy as np
import base64
import json
import os
import sys
import signal
import logging
from pathlib import Path
from typing import Dict, List, Optional, Union

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('video_stream_server')

class VideoStreamServer:
    def __init__(self, port: int = 8080):
        self.port = port
        self.clients = set()
        self.is_playing = False
        self.current_frame = 0
        
        # Video state
        self.current_videos: Dict[str, Dict] = {}  # Path -> video info
        self.video_cache: Dict[str, cv2.VideoCapture] = {}
        self.frame_rate = 30  # Default frame rate
        self.total_frames = 600  # Default 20 seconds at 30fps
        
        # Playback control
        self.play_task = None
        self.shutdown_event = asyncio.Event()
        
        logger.info(f"Video stream server initialized on port {self.port}")

    async def register(self, websocket):
        self.clients.add(websocket)
        logger.info(f"Client connected. Total clients: {len(self.clients)}")

    async def unregister(self, websocket):
        self.clients.remove(websocket)
        logger.info(f"Client disconnected. Total clients: {len(self.clients)}")

    async def send_frame_to_all(self, frame_data: str):
        """Send a frame to all connected clients."""
        if not self.clients:
            return
            
        disconnected_clients = set()
        for client in self.clients:
            try:
                await client.send(frame_data)
            except websockets.exceptions.ConnectionClosed:
                disconnected_clients.add(client)
                
        # Remove disconnected clients
        for client in disconnected_clients:
            await self.unregister(client)

    def get_frame(self, frame_index: int) -> Optional[bytes]:
        """Get a composite frame at the specified index."""
        # If no videos are loaded, return a blank frame
        if not self.current_videos:
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
        
        # Create a black background frame
        composite_frame = np.zeros((720, 1280, 3), dtype=np.uint8)
        
        # Flag to check if we actually rendered any videos
        videos_rendered = False
        
        # Process each video in the timeline
        for video_path, video_info in self.current_videos.items():
            # Check if the frame is within this video's time range
            start_frame = video_info.get('start_frame', 0)
            end_frame = video_info.get('end_frame', self.total_frames)
            
            # Exact frame comparison - the frame must be exactly within the clip's range
            if start_frame <= frame_index <= end_frame:
                # Calculate the frame offset within the source video
                source_start_frame = video_info.get('source_start_frame', 0)
                # Ensure exact frame calculation
                source_frame_index = source_start_frame + (frame_index - start_frame)
                
                logger.debug(f"Rendering frame: timeline={frame_index}, clip={video_path}, " +
                           f"range={start_frame}-{end_frame}, source_frame={source_frame_index}")
                
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
                
                # Resize and position the frame according to preview_rect
                preview_rect = video_info.get('preview_rect', {'left': 0, 'top': 0, 'width': 640, 'height': 360})
                x = int(preview_rect['left'])
                y = int(preview_rect['top'])
                width = int(preview_rect['width'])
                height = int(preview_rect['height'])
                
                # Resize the frame
                resized_frame = cv2.resize(frame, (width, height))
                
                # Apply flip if needed
                flip_type = video_info.get('flip', 0)
                if flip_type == 1:  # Horizontal
                    resized_frame = cv2.flip(resized_frame, 1)
                elif flip_type == 2:  # Vertical
                    resized_frame = cv2.flip(resized_frame, 0)
                
                # Check if the area is within the composite frame
                if (x >= 0 and y >= 0 and 
                    x + width <= composite_frame.shape[1] and 
                    y + height <= composite_frame.shape[0]):
                    
                    # Create an alpha blend
                    alpha = 1.0  # Full opacity for now
                    
                    # Place the frame on the composite image
                    composite_frame[y:y+height, x:x+width] = resized_frame
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
        if not videos_rendered:
            # Add text explaining the issue
            cv2.putText(
                composite_frame, 
                "No clips visible at current frame", 
                (400, 360), 
                cv2.FONT_HERSHEY_SIMPLEX, 
                1, 
                (255, 255, 255), 
                2
            )
            cv2.putText(
                composite_frame, 
                f"Current frame: {frame_index}", 
                (500, 400), 
                cv2.FONT_HERSHEY_SIMPLEX, 
                0.7, 
                (200, 200, 200), 
                1
            )
        
        # Encode the composite frame
        _, buffer = cv2.imencode('.jpg', composite_frame)
        return buffer.tobytes()

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

    def update_videos(self, video_data: List[Dict]):
        """Update the list of videos in the timeline."""
        # Clear old videos
        self.current_videos.clear()
        
        if not video_data:
            logger.info("Received empty video data - clearing all videos")
            return
            
        logger.info(f"Updating videos: received {len(video_data)} videos for timeline")
        
        # Add new videos
        video_count = 0
        for video in video_data:
            path = video.get('path')
            if not path:
                logger.warning("Skipped video with missing path")
                continue
                
            if not os.path.exists(path):
                logger.warning(f"Video file not found: {path}")
                continue
                
            # Store the video configuration
            self.current_videos[path] = video
            video_count += 1
            
            # Log some basic info about the video
            preview_rect = video.get('preview_rect', {})
            pos_info = f"pos: {preview_rect.get('left', 0)},{preview_rect.get('top', 0)}"
            time_info = f"frames: {video.get('start_frame', 0)}-{video.get('end_frame', 0)}"
            logger.info(f"Added video: {os.path.basename(path)}, {pos_info}, {time_info}")
                
            # Update frame rate and total frames if needed
            if 'frame_rate' in video:
                self.frame_rate = video['frame_rate']
                logger.debug(f"Updated frame rate to {self.frame_rate}")
                
            if 'end_frame' in video:
                self.total_frames = max(self.total_frames, video['end_frame'])
                logger.debug(f"Updated total frames to {self.total_frames}")
                    
        logger.info(f"Timeline updated: {video_count} valid videos added")
        
        # If we have no videos after processing, set the default empty state
        if not self.current_videos:
            logger.warning("No valid videos found in the data")
            self.total_frames = 600  # Reset to default

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

    async def handle_message(self, websocket, message: str):
        """Handle incoming messages from clients."""
        try:
            if message == "play":
                await self.start_playback()
                # Send state update to confirm play state
                await self._send_state_update(websocket, True)
            elif message == "pause":
                await self.stop_playback()
                # Send state update to confirm pause state
                await self._send_state_update(websocket, False)
            elif message.startswith("seek:"):
                # Format: seek:123 (frame number)
                try:
                    frame = int(message.split(':')[1])
                    
                    # Ensure the frame is within valid range
                    old_frame = self.current_frame
                    self.current_frame = max(0, min(frame, self.total_frames - 1))
                    
                    # Log frame changes for debugging timing issues
                    if abs(old_frame - self.current_frame) > 1 or frame % 30 == 0:
                        logger.info(f"Seek request: {frame}, actual: {self.current_frame}")
                    
                    # Always stop playback during manual seeking to prevent auto-play
                    was_playing = self.is_playing
                    if self.is_playing:
                        await self.stop_playback()
                    
                    # Send the current frame immediately
                    frame_bytes = self.get_frame(self.current_frame)
                    if frame_bytes:
                        encoded_frame = base64.b64encode(frame_bytes).decode('utf-8')
                        await websocket.send(encoded_frame)
                    
                    # Confirm to client that we're in paused state after seeking
                    await self._send_state_update(websocket, False)
                    
                    # Only resume playback if explicitly requested with a "play" command
                    # Remove auto-resume to fix the playback issue during seek
                except ValueError:
                    logger.error(f"Invalid frame number in seek command: {message}")
            elif message.startswith("videos:"):
                # Format: videos:<json_data>
                json_str = message[7:]  # Remove "videos:" prefix
                try:
                    video_data = json.loads(json_str)
                    self.update_videos(video_data)
                except json.JSONDecodeError:
                    logger.error(f"Invalid JSON in videos message: {json_str}")
            else:
                logger.warning(f"Unknown command: {message}")
                
        except Exception as e:
            logger.error(f"Error handling message: {e}")
            
    async def _send_state_update(self, websocket, is_playing: bool):
        """Send a state update message to the client with current playback state."""
        try:
            # Ensure compact JSON with no space after colon to match what Flutter expects
            state_message = json.dumps({
                "type": "state", 
                "playing": is_playing,
                "frame": self.current_frame
            }, separators=(',', ':'))
            await websocket.send(state_message)
            logger.debug(f"Sent state update: {state_message[:50]}...")
        except Exception as e:
            logger.error(f"Error sending state update: {e}")
            
    async def handler(self, websocket, path=''):
        """Handle WebSocket connections."""
        await self.register(websocket)
        try:
            async for message in websocket:
                await self.handle_message(websocket, message)
        except websockets.exceptions.ConnectionClosed:
            logger.info("Connection closed")
        finally:
            await self.unregister(websocket)

    async def run(self):
        """Run the WebSocket server."""
        # Create the server with a handler that includes the path parameter
        server = await websockets.serve(self.handler, "0.0.0.0", self.port)
        
        logger.info(f"Server started on port {self.port}")
        
        # Wait for the shutdown event
        await self.shutdown_event.wait()
        
        # Close the server when shutting down
        server.close()
        await server.wait_closed()
        
        logger.info("Server shut down")

    def shutdown(self):
        """Shutdown the server."""
        logger.info("Shutting down server...")
        self.shutdown_event.set()
        
        # Clean up video captures
        for cap in self.video_cache.values():
            cap.release()
        self.video_cache.clear()


async def main():
    # Create and run the server
    server = VideoStreamServer()
    
    # Handle signals
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, server.shutdown)
    
    # Run the server
    await server.run()

if __name__ == "__main__":
    asyncio.run(main())
