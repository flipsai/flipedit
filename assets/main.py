#!/usr/bin/env python3
import asyncio
import signal
import logging
from typing import Any, List, Dict, Optional

# Import the refactored modules
import config
import http_server
import websocket_server
import timeline_manager
import frame_generator
import playback_controller
import message_handler

# Global logger instance
logger: Optional[logging.Logger] = None

class MainServer:
    def __init__(self, args):
        """Initialize the main server coordinating all components."""
        global logger
        logger = config.configure_logging(args)
        
        self.args = args
        
        # Initialize components
        self.timeline_manager = timeline_manager.TimelineManager()
        self.frame_generator = frame_generator.FrameGenerator()
        
        # Pass callbacks to the PlaybackController
        self.playback_controller = playback_controller.PlaybackController(
            frame_getter_callback=self.get_frame_for_playback,
            send_frame_callback=self.send_frame_to_all_clients
        )
        
        # Pass callbacks to the MessageHandler
        self.message_handler_instance = message_handler.MessageHandler(
            update_timeline_callback=self.handle_update_timeline,
            start_playback_callback=self.playback_controller.start_playback,
            stop_playback_callback=self.playback_controller.stop_playback,
            seek_callback=self.handle_seek,
            get_frame_callback=self.get_frame_for_seek,
            send_state_callback=self.send_state_update_to_client
        )
        
        # Pass the message handling callback to the WebSocketServer
        self.ws_server = websocket_server.WebSocketServer(
            port=args.ws_port,
            host=args.host,
            message_handler_callback=self.message_handler_instance.handle_message
        )
        
        self.http_server_instance = None # Will be set in run()

    def get_frame_for_playback(self, frame_index: int) -> Optional[bytes]:
        """Wrapper to get frame using current timeline state for playback loop"""
        timeline_state = self.timeline_manager.get_timeline_state()
        return self.frame_generator.get_frame(
            frame_index,
            timeline_state["videos"],
            timeline_state["total_frames"]
        )

    async def send_frame_to_all_clients(self, frame_data: str):
        """Wrapper to send frame data via WebSocket server"""
        await self.ws_server.send_frame_to_all(frame_data)

    def handle_update_timeline(self, video_data: List[Dict]):
        """Handle timeline updates and propagate changes"""
        self.timeline_manager.update_videos(video_data)
        timeline_state = self.timeline_manager.get_timeline_state()
        # Update playback controller with new timeline parameters
        self.playback_controller.set_timeline_params(
            timeline_state["frame_rate"],
            timeline_state["total_frames"]
        )

    def handle_seek(self, frame: int) -> int:
        """Handle seek command and return the actual seeked frame"""
        return self.playback_controller.seek(frame)

    def get_frame_for_seek(self, frame_index: int) -> Optional[bytes]:
        """Get a specific frame for seek response"""
        return self.get_frame_for_playback(frame_index)

    async def send_state_update_to_client(self, websocket: Any, is_playing: bool):
        """Send playback state update to a specific client"""
        playback_state = self.playback_controller.get_playback_state()
        await self.ws_server.send_state_update(
            websocket,
            playback_state["playing"], # Use the definitive state from playback_controller
            playback_state["current_frame"]
        )

    def setup_signal_handlers(self):
        """Set up signal handlers for graceful shutdown"""
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, self.shutdown)
        logger.info("Signal handlers registered for SIGINT and SIGTERM.")

    async def run(self):
        """Run the HTTP and WebSocket servers."""
        logger.info(f"Starting FlipEdit Video Stream Server")
        logger.info(f"WebSocket server on port {self.args.ws_port}")
        logger.info(f"HTTP API server on port {self.args.http_port}")
        
        # Start the HTTP server
        self.http_server_instance = http_server.run_http_server(
            host=self.args.host, 
            port=self.args.http_port
        )
        
        # Set up signal handlers
        self.setup_signal_handlers()
        
        # Run the WebSocket server (which waits for shutdown)
        await self.ws_server.run()
        
        # Cleanup after WebSocket server finishes
        self.perform_cleanup()

    def shutdown(self):
        """Initiate graceful shutdown of all components."""
        if logger: # Check if logger is initialized
            logger.info("Shutdown requested...")
        
        # Signal playback controller to stop
        self.playback_controller.shutdown()
        
        # Signal WebSocket server to shut down
        self.ws_server.shutdown()
        
        # Shutdown HTTP server (needs to be done carefully from main thread)
        # The thread is daemonized, but explicit shutdown is cleaner
        if self.http_server_instance:
            self.http_server_instance.shutdown()
        
    def perform_cleanup(self):
        """Perform cleanup tasks after servers have stopped."""
        if logger:
             logger.info("Performing cleanup...")
        self.frame_generator.cleanup() # Release OpenCV resources
        if logger:
             logger.info("Server shutdown complete.")

async def main():
    # Parse command-line arguments
    args = config.parse_args()
    
    # Create and run the main server application
    main_server = MainServer(args)
    await main_server.run()

if __name__ == "__main__":
    asyncio.run(main())