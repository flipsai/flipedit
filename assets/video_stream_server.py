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
        # Change current_videos to a list to handle multiple clips from the same source
        self.current_videos: List[Dict] = []
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
        
        # Process each video clip in the timeline list
        for video_info in self.current_videos:
            video_path = video_info.get('sourcePath')
            if not video_path:
                 logger.warning("Skipping clip with no sourcePath in get_frame")
                 continue

            # Get frame times (using the calculated frames from update_videos if available)
            start_frame_calc = video_info.get('start_frame_calc', 0) # Use calculated frame number
            end_frame_calc = video_info.get('end_frame_calc', self.total_frames) # Use calculated frame number

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
                
                # Log updated to reflect variable names
                # logger.debug(f"Rendering frame: timeline={frame_index}, clip={os.path.basename(video_path)}, " +
                #            f"range={start_frame_calc}-{end_frame_calc} (calc), source_frame={source_frame_index} (calc)") # Redundant with above logs
                
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
        # Clear old videos list
        old_video_count = len(self.current_videos)
        self.current_videos.clear()
        logger.debug(f"Cleared {old_video_count} old video entries.")
        
        if not video_data:
            logger.info("Received empty video data - clearing all videos")
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
            elif message.startswith('{"type":"clips"'): # Check for the new JSON format
                try:
                    data = json.loads(message)
                    if data.get('type') == 'clips':
                        video_data = data.get('data', [])
                        logger.info(f"Received 'clips' message with {len(video_data)} clips.")
                        # Log the received raw data (truncated)
                        truncated_data = str(video_data)[:500]
                        logger.debug(f"Raw clips data received (truncated): {truncated_data}")
                        self.update_videos(video_data)
                    else:
                        logger.warning(f"Received JSON message with unknown type: {data.get('type')}")
                except json.JSONDecodeError as e:
                    logger.error(f"Invalid JSON received: {message[:200]}... Error: {e}")
                except Exception as e:
                    logger.error(f"Error processing 'clips' message: {e}")
            elif message.startswith("videos:"): # Keep old format for compatibility if needed? Or remove? Assuming new format replaces old.
                # Format: videos:<json_data> - This path might be deprecated now
                logger.warning("Received message in deprecated 'videos:' format. Processing anyway.")
                json_str = message[7:]  # Remove "videos:" prefix
                try:
                    video_data = json.loads(json_str)
                    self.update_videos(video_data)
                except json.JSONDecodeError:
                    logger.error(f"Invalid JSON in videos message: {json_str}")
            else:
                logger.warning(f"Unknown command received: {message[:100]}...") # Log only the start of unknown messages
                
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
