#!/usr/bin/env python3
"""
FlipEdit Frame Generator Server - New WebSocket Approach
Sends frame data TO Flutter instead of writing to texture pointers
"""
import asyncio
import websockets
import json
import argparse
import logging
import cv2
import numpy as np
import base64
from typing import Set, Optional
import time

# Configure logging
logging.basicConfig(
    level=logging.INFO, 
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("FrameGenerator")

class FlipEditFrameGenerator:
    """
    Modern frame generator that sends RGBA frame data to Flutter via WebSocket
    No more texture pointers - just clean WebSocket communication
    """
    
    def __init__(self):
        # Frame properties
        self.width = 1920
        self.height = 1080
        self.fps = 30
        
        # State management
        self.running = False
        self.playback_active = False
        self.current_frame = 0
        self.frame_task: Optional[asyncio.Task] = None
        
        # WebSocket clients
        self.connected_clients: Set[websockets.WebSocketServerProtocol] = set()
        
        # Timing
        self.last_frame_time = 0
        
        logger.info("FlipEdit Frame Generator initialized")
    
    async def initialize(self):
        """Initialize the frame generator (camera, etc.)"""
        if self.running:
            return
            
        logger.info(f"Initializing frame generator for {self.width}x{self.height}")
        
        self.running = True
        
        # Start frame generation task
        self.frame_task = asyncio.create_task(self._frame_generation_loop())
        logger.info("Frame generation task started")
    
    async def shutdown(self):
        """Shutdown the frame generator"""
        logger.info("Shutting down frame generator")
        
        self.running = False
        self.playback_active = False
        
        # Stop frame generation task
        if self.frame_task:
            self.frame_task.cancel()
            try:
                await self.frame_task
            except asyncio.CancelledError:
                pass
            self.frame_task = None
        
        # Clear clients
        self.connected_clients.clear()
        
        logger.info("Frame generator shutdown complete")
    
    def set_dimensions(self, width: int, height: int):
        """Update frame dimensions"""
        self.width = width
        self.height = height
        logger.info(f"Set dimensions: {width}x{height}")
    
    def start_playback(self, fps: int = 30, current_frame: int = 0):
        """Start continuous playback"""
        self.playback_active = True
        self.fps = max(1, fps)  # Ensure valid FPS
        self.current_frame = current_frame
        logger.info(f"Playback started: frame {current_frame}, FPS {fps}")
    
    def stop_playback(self):
        """Stop continuous playback"""
        self.playback_active = False
        logger.info("Playback stopped")
    
    async def render_frame(self, frame_number: int):
        """Render and send a specific frame"""
        self.current_frame = frame_number
        frame = self._generate_frame()
        
        if frame is not None:
            await self._send_frame_to_clients(frame)
            logger.info(f"Rendered specific frame: {frame_number}")
    
    def add_client(self, websocket):
        """Add WebSocket client"""
        self.connected_clients.add(websocket)
        logger.info(f"Client connected. Total: {len(self.connected_clients)}")
    
    def remove_client(self, websocket):
        """Remove WebSocket client"""
        self.connected_clients.discard(websocket)
        logger.info(f"Client disconnected. Total: {len(self.connected_clients)}")
    
    async def _frame_generation_loop(self):
        """Main frame generation loop"""
        logger.info("Frame generation loop started")
        
        while self.running:
            try:
                if not self.playback_active or not self.connected_clients:
                    # No playback or no clients - just wait
                    await asyncio.sleep(0.1)
                    continue
                
                # Frame timing
                current_time = time.time()
                elapsed = current_time - self.last_frame_time
                target_interval = 1.0 / self.fps
                
                if elapsed < target_interval:
                    await asyncio.sleep(target_interval - elapsed)
                
                # Generate and send frame
                frame = self._generate_frame()
                if frame is not None:
                    await self._send_frame_to_clients(frame)
                    self.current_frame += 1
                
                self.last_frame_time = time.time()
                
            except asyncio.CancelledError:
                logger.info("Frame generation loop cancelled")
                break
            except Exception as e:
                logger.error(f"Error in frame generation loop: {e}")
                await asyncio.sleep(0.1)  # Brief pause on error
        
        logger.info("Frame generation loop ended")
    
    def _generate_frame(self):
        """Generate a single frame"""
        # Generate animated test frame (replace this with your video processing logic)
        return self._generate_test_frame()
    
    def _generate_test_frame(self):
        """Generate an animated test pattern
        
        TODO: Replace this method with your actual video processing logic.
        This is where you should:
        1. Load video frames from your FlipEdit timeline
        2. Apply OpenCV effects/filters
        3. Return the processed frame
        """
        # Create base image
        frame = np.zeros((self.height, self.width, 3), dtype=np.uint8)
        
        # Animation time
        t = self.current_frame / self.fps
        
        # Animated gradient background
        y_indices, x_indices = np.mgrid[0:self.height, 0:self.width]
        
        # Create wave patterns
        r = (128 + 127 * np.sin(x_indices / 200.0 + t * 2.0)).astype(np.uint8)
        g = (128 + 127 * np.sin(y_indices / 150.0 + t * 1.5)).astype(np.uint8)  
        b = (128 + 127 * np.sin((x_indices + y_indices) / 300.0 + t)).astype(np.uint8)
        
        frame[:, :, 0] = b  # BGR format
        frame[:, :, 1] = g
        frame[:, :, 2] = r
        
        # Add moving circles
        for i in range(3):
            center_x = int(self.width/2 + 250 * np.sin(t * 0.8 + i * 2.1))
            center_y = int(self.height/2 + 180 * np.cos(t * 1.2 + i * 1.7))
            center_x = max(100, min(self.width - 100, center_x))
            center_y = max(100, min(self.height - 100, center_y))
            
            radius = int(60 + 30 * np.sin(t * 3 + i))
            color = (255, 255, 255)  # White
            cv2.circle(frame, (center_x, center_y), radius, color, 4)
        
        # Add info overlay
        self._add_info_overlay(frame)
        
        return frame
    
    def _add_info_overlay(self, frame):
        """Add information overlay to frame"""
        info_lines = [
            f"FlipEdit Frame Generator",
            f"Frame: {self.current_frame}",
            f"FPS: {self.fps}",
            f"Size: {self.width}x{self.height}",
            f"Mode: Generated",
            f"Clients: {len(self.connected_clients)}",
            f"Playback: {'ON' if self.playback_active else 'OFF'}"
        ]
        
        # Semi-transparent background for text
        overlay = frame.copy()
        cv2.rectangle(overlay, (20, 20), (400, 20 + len(info_lines) * 35 + 20), 
                     (0, 0, 0), -1)
        cv2.addWeighted(overlay, 0.7, frame, 0.3, 0, frame)
        
        # Add text
        for i, line in enumerate(info_lines):
            y_pos = 50 + i * 35
            cv2.putText(frame, line, (30, y_pos), cv2.FONT_HERSHEY_SIMPLEX, 
                       0.8, (255, 255, 255), 2)
    
    async def _send_frame_to_clients(self, frame):
        """Convert frame to RGBA and send to all connected clients"""
        if not self.connected_clients:
            return
        
        try:
            # Convert BGR to RGBA
            rgba_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGBA)
            
            # Encode frame data
            frame_bytes = rgba_frame.tobytes()
            frame_b64 = base64.b64encode(frame_bytes).decode('utf-8')
            
            # Create message
            message = {
                'command': 'frame_data',
                'frame_data': frame_b64,
                'width': self.width,
                'height': self.height,
                'frame_number': self.current_frame,
                'timestamp': time.time()
            }
            
            message_json = json.dumps(message)
            
            # Send to all clients (remove disconnected ones)
            disconnected = set()
            for client in self.connected_clients.copy():
                try:
                    await client.send(message_json)
                except websockets.exceptions.ConnectionClosed:
                    disconnected.add(client)
                except Exception as e:
                    logger.warning(f"Error sending to client: {e}")
                    disconnected.add(client)
            
            # Clean up disconnected clients
            self.connected_clients -= disconnected
            
        except Exception as e:
            logger.error(f"Error preparing/sending frame: {e}")

async def handle_websocket_connection(websocket, frame_generator):
    """Handle individual WebSocket connection"""
    client_addr = websocket.remote_address
    logger.info(f"Client connected: {client_addr}")
    
    frame_generator.add_client(websocket)
    
    try:
        async for message in websocket:
            try:
                data = json.loads(message)
                command = data.get("command", "")
                
                # Handle commands
                if command == "set_texture_ptr":
                    # Initialize with dimensions (legacy compatibility)
                    width = int(data.get("width", 1920))
                    height = int(data.get("height", 1080))
                    
                    frame_generator.set_dimensions(width, height)
                    await frame_generator.initialize()
                    
                    response = {
                        "status": "success",
                        "message": f"Frame generator initialized: {width}x{height}"
                    }
                    logger.info(f"Initialized: {width}x{height}")
                    
                elif command == "start_playback":
                    fps = int(data.get("frame_rate", 30))
                    current_frame = int(data.get("current_frame", 0))
                    
                    frame_generator.start_playback(fps, current_frame)
                    
                    response = {
                        "status": "success",
                        "message": f"Playback started: frame {current_frame}, FPS {fps}"
                    }
                    
                elif command == "stop_playback":
                    current_frame = int(data.get("current_frame", 0))
                    
                    frame_generator.stop_playback()
                    
                    response = {
                        "status": "success", 
                        "message": f"Playback stopped at frame {current_frame}"
                    }
                    
                elif command == "render_frame":
                    frame_number = int(data.get("frame", 0))
                    
                    await frame_generator.render_frame(frame_number)
                    
                    response = {
                        "status": "success",
                        "message": f"Rendered frame {frame_number}"
                    }
                    
                elif command == "ping":
                    response = {
                        "status": "success",
                        "message": "pong"
                    }
                    
                elif command == "dispose_texture":
                    await frame_generator.shutdown()
                    
                    response = {
                        "status": "success",
                        "message": "Frame generator stopped"
                    }
                    
                elif command == "shutdown":
                    logger.info("Shutdown command received")
                    await frame_generator.shutdown()
                    
                    response = {
                        "status": "success",
                        "message": "Server shutting down"
                    }
                    
                    # Send response then shutdown
                    await websocket.send(json.dumps(response))
                    asyncio.create_task(_shutdown_server())
                    return
                    
                else:
                    response = {
                        "status": "error",
                        "message": f"Unknown command: {command}"
                    }
                    logger.warning(f"Unknown command from {client_addr}: {command}")
                
                # Send response
                await websocket.send(json.dumps(response))
                
            except json.JSONDecodeError as e:
                error_response = {
                    "status": "error",
                    "message": f"Invalid JSON: {str(e)}"
                }
                await websocket.send(json.dumps(error_response))
                logger.error(f"JSON decode error from {client_addr}: {e}")
                
            except Exception as e:
                error_response = {
                    "status": "error", 
                    "message": f"Command processing error: {str(e)}"
                }
                await websocket.send(json.dumps(error_response))
                logger.error(f"Command error from {client_addr}: {e}")
                
    except websockets.exceptions.ConnectionClosed:
        logger.info(f"Client disconnected: {client_addr}")
    except Exception as e:
        logger.error(f"WebSocket error with {client_addr}: {e}")
    finally:
        frame_generator.remove_client(websocket)

async def _shutdown_server():
    """Shutdown the server gracefully"""
    await asyncio.sleep(0.1)  # Brief delay to send final response
    logger.info("Server shutting down...")
    
    # Stop the event loop
    loop = asyncio.get_running_loop()
    loop.stop()

async def main():
    """Main server entry point"""
    parser = argparse.ArgumentParser(
        description="FlipEdit Frame Generator - WebSocket Server"
    )
    parser.add_argument('--host', default='0.0.0.0', 
                       help='Host to bind server to (default: 0.0.0.0)')
    parser.add_argument('--ws-port', type=int, default=8080,
                       help='WebSocket port (default: 8080)')
    
    args = parser.parse_args()
    
    # Create frame generator
    frame_generator = FlipEditFrameGenerator()
    
    try:
        # Start WebSocket server
        logger.info(f"Starting WebSocket server on {args.host}:{args.ws_port}")
        
        server = await websockets.serve(
            lambda ws: handle_websocket_connection(ws, frame_generator),
            args.host,
            args.ws_port,
            ping_interval=20,  # Keep connections alive
            ping_timeout=10
        )
        
        logger.info(f"Python WebSocket server listening on {args.host}:{args.ws_port}")
        
        # Wait for server to close
        await server.wait_closed()
        
    except Exception as e:
        logger.error(f"Server error: {e}")
        raise
    finally:
        # Ensure cleanup
        await frame_generator.shutdown()
        logger.info("Server cleanup complete")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Server stopped by user (Ctrl+C)")
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
