import asyncio
import websockets
import cv2
import base64
import time
import argparse
import logging
import os
import numpy as np
import threading
import queue
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('video-stream-server')

# Default settings
DEFAULT_VIDEO_PATH_1 = "./sample_video_1.mp4"  # First video file path
DEFAULT_VIDEO_PATH_2 = "./sample_video_2.mp4"  # Second video file path
DEFAULT_HOST = "localhost"
DEFAULT_PORT = 8080
DEFAULT_FPS = 30
DEFAULT_QUALITY = 70  # JPEG quality (0-100) - reduced for better performance

class VideoStreamServer:
    def __init__(self, video_path_1, video_path_2, host, port, target_fps, jpeg_quality):
        self.video_path_1 = video_path_1
        self.video_path_2 = video_path_2
        self.host = host
        self.port = port
        self.target_fps = target_fps
        self.frame_interval = 1.0 / target_fps
        self.jpeg_quality = jpeg_quality
        self.connected_clients = set()
        self._stop_event = threading.Event()
        self._frame_queue = queue.Queue(maxsize=5) # Limit queue size
        self._processing_thread = None
        self._is_paused = False # Add pause state flag
        self._pause_lock = threading.Lock() # Lock for thread-safe access to pause state
        
        # Validate video files
        if not os.path.exists(video_path_1):
            raise FileNotFoundError(f"Video file 1 not found: {video_path_1}")
        if not os.path.exists(video_path_2):
            raise FileNotFoundError(f"Video file 2 not found: {video_path_2}")
        
        logger.info(f"Initialized server with videos: {video_path_1} and {video_path_2}")
        logger.info(f"Target FPS: {target_fps}, JPEG quality: {jpeg_quality}")

    async def handle_client(self, websocket):
        """Handle a client connection"""
        client_info = f"{websocket.remote_address[0]}:{websocket.remote_address[1]}"
        logger.info(f"New client connected: {client_info}")
        
        self.connected_clients.add(websocket)
        logger.info(f"Client {client_info} added. Total clients: {len(self.connected_clients)}")
        try:
            # Listen for messages from the client (play/pause commands)
            async for message in websocket:
                logger.debug(f"Received message from {client_info}: {message}")
                if message == "pause":
                    with self._pause_lock:
                        self._is_paused = True
                    logger.info("Received pause command.")
                elif message == "play":
                    with self._pause_lock:
                        self._is_paused = False
                    logger.info("Received play command.")
                else:
                    logger.warning(f"Received unknown command: {message}")
        except websockets.exceptions.ConnectionClosedOK:
            logger.info(f"Client {client_info} disconnected normally.")
        except websockets.exceptions.ConnectionClosedError as e:
            logger.warning(f"Client {client_info} disconnected with error: {e}")
        except Exception as e:
            logger.error(f"Error handling client {client_info}: {e}")
        finally:
            # Remove client when disconnected
            if websocket in self.connected_clients:
                self.connected_clients.remove(websocket)
            logger.info(f"Client {client_info} removed. Total clients: {len(self.connected_clients)}")

    def _process_frames_thread(self):
        """Dedicated thread for reading, processing, and encoding frames."""
        # Open both video sources
        cap1 = cv2.VideoCapture(self.video_path_1)
        cap2 = cv2.VideoCapture(self.video_path_2)
        
        if not cap1.isOpened() or not cap2.isOpened():
            logger.error("Error opening one or both video sources in processing thread.")
            if cap1.isOpened(): cap1.release()
            if cap2.isOpened(): cap2.release()
            return

        # Get video properties and calculate target dimensions
        frame_width_1 = int(cap1.get(cv2.CAP_PROP_FRAME_WIDTH))
        frame_height_1 = int(cap1.get(cv2.CAP_PROP_FRAME_HEIGHT))
        frame_width_2 = int(cap2.get(cv2.CAP_PROP_FRAME_WIDTH))
        frame_height_2 = int(cap2.get(cv2.CAP_PROP_FRAME_HEIGHT))

        scale_factor = 0.5
        target_height = int(max(frame_height_1, frame_height_2) * scale_factor)
        target_width_1 = int(frame_width_1 * scale_factor)
        target_width_2 = int(frame_width_2 * scale_factor)
        combined_width = target_width_1 + target_width_2
        combined_height = target_height

        combined_frame = np.zeros((combined_height, combined_width, 3), dtype=np.uint8)
        encode_params = [cv2.IMWRITE_JPEG_QUALITY, self.jpeg_quality]
        
        logger.info("Video processing thread started.")

        try:
            while not self._stop_event.is_set():
                # Check pause state before processing
                with self._pause_lock:
                    is_paused_now = self._is_paused
                
                if is_paused_now:
                    # If paused, sleep briefly and continue loop without processing
                    time.sleep(0.1)
                    continue

                frame_start_time = time.time()

                # Read frames
                ret1, frame1 = cap1.read()
                ret2, frame2 = cap2.read()

                # Loop videos if ended
                if not ret1:
                    cap1.set(cv2.CAP_PROP_POS_FRAMES, 0)
                    ret1, frame1 = cap1.read()
                    if not ret1: continue # Skip if reading fails after reset
                if not ret2:
                    cap2.set(cv2.CAP_PROP_POS_FRAMES, 0)
                    ret2, frame2 = cap2.read()
                    if not ret2: continue # Skip if reading fails after reset

                # Process frames
                frame1_resized = cv2.resize(frame1, (target_width_1, target_height), interpolation=cv2.INTER_AREA)
                frame2_resized = cv2.resize(frame2, (target_width_2, target_height), interpolation=cv2.INTER_AREA)
                combined_frame[:, :target_width_1] = frame1_resized
                combined_frame[:, target_width_1:] = frame2_resized
                
                # Encode frame
                ret, buffer = cv2.imencode('.jpg', combined_frame, encode_params)
                if not ret:
                    logger.warning("Failed to encode frame.")
                    continue

                # Convert to base64
                frame_data = base64.b64encode(buffer).decode('utf-8')
                
                # Put frame in queue (blocking if full)
                try:
                    self._frame_queue.put(frame_data, timeout=1) # Add timeout to prevent indefinite block
                except queue.Full:
                    logger.warning("Frame queue is full, dropping frame.")
                    # If queue is full, drop the oldest frame to make space for the new one
                    try:
                        self._frame_queue.get_nowait()
                        self._frame_queue.put(frame_data, timeout=0.1)
                    except queue.Empty:
                        pass # Should not happen if Full was raised, but handle anyway
                    except queue.Full:
                        pass # Still full after dropping, give up on this frame

                # Control processing rate (approximate)
                elapsed = time.time() - frame_start_time
                sleep_time = max(0, self.frame_interval - elapsed)
                time.sleep(sleep_time) # Use time.sleep in thread

        finally:
            cap1.release()
            cap2.release()
            logger.info("Video processing thread finished.")

    async def broadcast_frames(self):
        """Broadcasts frames from the queue to connected clients."""
        frame_count = 0
        start_time = time.time()
        
        while not self._stop_event.is_set():
            try:
                # Get frame from queue (non-blocking)
                frame_data = self._frame_queue.get_nowait()
            except queue.Empty:
                # No frame ready, wait briefly
                await asyncio.sleep(0.01)
                continue

            # Send frame to all connected clients
            if self.connected_clients:
                # Create tasks for sending to avoid blocking
                tasks = [client.send(frame_data) for client in self.connected_clients]
                results = await asyncio.gather(*tasks, return_exceptions=True)
                
                # Handle potential errors during send (e.g., client disconnected)
                for i, result in enumerate(results):
                    if isinstance(result, Exception):
                         # Find the client associated with the exception if needed
                         # client = list(self.connected_clients)[i]
                         logger.warning(f"Error sending frame to client: {result}")
                         # Consider removing the client here if the error indicates disconnection

            # Update statistics
            frame_count += 1
            
            # Log statistics periodically
            if frame_count % 100 == 0:
                total_elapsed = time.time() - start_time
                if total_elapsed > 0:
                    actual_fps = frame_count / total_elapsed
                    logger.info(f"Sent {frame_count} frames, current FPS: {actual_fps:.2f}, Queue size: {self._frame_queue.qsize()}")
                else:
                    logger.info(f"Sent {frame_count} frames, Queue size: {self._frame_queue.qsize()}")

            # Let the event loop run other tasks
            await asyncio.sleep(0) # Yield control briefly

    async def start_server(self):
        """Start the WebSocket server and the processing thread"""
        # Start the frame processing thread
        self._stop_event.clear()
        self._processing_thread = threading.Thread(target=self._process_frames_thread, daemon=True)
        self._processing_thread.start()
        
        server = await websockets.serve(self.handle_client, self.host, self.port)
        logger.info(f"WebSocket server started on ws://{self.host}:{self.port}")
        
        # Start the frame broadcaster task
        broadcast_task = asyncio.create_task(self.broadcast_frames())
        
        try:
            # Run the server indefinitely
            await asyncio.Future()
        finally:
            logger.info("Shutting down server...")
            self._stop_event.set() # Signal processing thread to stop
            if self._processing_thread:
                self._processing_thread.join(timeout=2) # Wait for thread to finish
            broadcast_task.cancel() # Cancel the broadcast task
            try:
                 await broadcast_task # Wait for cancellation
            except asyncio.CancelledError:
                 logger.info("Broadcast task cancelled.")
            server.close()
            await server.wait_closed()
            logger.info("Server shut down complete.")

def parse_arguments():
    parser = argparse.ArgumentParser(description='WebSocket Video Streaming Server')
    parser.add_argument('--video1', type=str, default=DEFAULT_VIDEO_PATH_1,
                        help=f'Path to first video file (default: {DEFAULT_VIDEO_PATH_1})')
    parser.add_argument('--video2', type=str, default=DEFAULT_VIDEO_PATH_2,
                        help=f'Path to second video file (default: {DEFAULT_VIDEO_PATH_2})')
    parser.add_argument('--host', type=str, default=DEFAULT_HOST,
                        help=f'Host address to bind (default: {DEFAULT_HOST})')
    parser.add_argument('--port', type=int, default=DEFAULT_PORT,
                        help=f'Port to bind (default: {DEFAULT_PORT})')
    parser.add_argument('--fps', type=int, default=DEFAULT_FPS,
                        help=f'Target FPS (default: {DEFAULT_FPS})')
    parser.add_argument('--quality', type=int, default=DEFAULT_QUALITY,
                        help=f'JPEG quality 1-100 (default: {DEFAULT_QUALITY})')
    return parser.parse_args()

async def main():
    # Parse command-line arguments
    args = parse_arguments()
    
    try:
        # Create and start the server
        server = VideoStreamServer(
            video_path_1=args.video1,
            video_path_2=args.video2,
            host=args.host,
            port=args.port,
            target_fps=args.fps,
            jpeg_quality=args.quality
        )
        
        await server.start_server()
    
    except FileNotFoundError as e:
        logger.error(e)
    except KeyboardInterrupt:
        logger.info("Server stopped by user")
    except Exception as e:
        logger.exception(f"Unexpected error: {e}")

if __name__ == "__main__":
    asyncio.run(main())