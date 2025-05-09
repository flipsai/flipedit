#!/usr/bin/env python3
import asyncio
import signal
import logging
from typing import Any, List, Dict, Optional
import threading

# Import the refactored modules
import config
import websocket_server
import timeline_manager as timeline_manager_module
# import frame_generator # Will be replaced by services
import playback_controller
import message_handler

# Import new video services
from video_services.timeline_state_service import TimelineStateService
from video_services.video_source_service import VideoSourceService
from video_services.frame_transform_service import FrameTransformService
from video_services.compositing_service import CompositingService
from video_services.encoding_service import EncodingService
from video_services.frame_cache_service import FrameCacheService # For intermediate frames
from video_services.frame_pipeline_service import FramePipelineService
import preview_server
import db_access

# Global logger instance
logger: Optional[logging.Logger] = None

# Global timeline manager instance for access from other modules
timeline_manager = None

def get_timeline_manager():
    """Get the global timeline manager instance."""
    return timeline_manager

class MainServer:
    def __init__(self, args):
        """Initialize the main server coordinating all components."""
        global logger, timeline_manager
        logger = config.configure_logging(args)
        
        # Parse arguments
        self.args = args
        
        # Create database manager based on configured path
        self.db_manager = db_access.get_manager()
        logger.info("Database manager initialized")
        if self.db_manager.metadata_db_path:
            logger.info(f"Found metadata database at: {self.db_manager.metadata_db_path}")
            projects = self.db_manager.get_project_list()
            logger.info(f"Found {len(projects)} projects in the database")
            if projects:
                logger.info(f"Most recent project: {projects[0]['name']}")
        
        # Initialize components
        self.timeline_manager = timeline_manager_module.TimelineManager()
        # Set the global timeline_manager for external access
        global timeline_manager
        timeline_manager = self.timeline_manager

        # --- Instantiate new video services ---
        self.timeline_state_service = TimelineStateService(
            canvas_width=self.args.default_canvas_width if hasattr(self.args, 'default_canvas_width') else 1280,
            canvas_height=self.args.default_canvas_height if hasattr(self.args, 'default_canvas_height') else 720
        )
        self.video_source_service = VideoSourceService()
        self.intermediate_frame_cache_service = FrameCacheService(max_cache_entries=120) # Cache for transformed clip frames
        self.frame_transform_service = FrameTransformService()
        self.compositing_service = CompositingService()
        self.encoding_service = EncodingService()
        
        self.frame_pipeline_service = FramePipelineService(
            timeline_state_service=self.timeline_state_service,
            video_source_service=self.video_source_service,
            frame_transform_service=self.frame_transform_service,
            compositing_service=self.compositing_service,
            encoding_service=self.encoding_service,
            intermediate_frame_cache_service=self.intermediate_frame_cache_service
        )
        # --- End new video services instantiation ---
        
        # self.frame_generator = frame_generator.FrameGenerator() # OLD
        
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
            get_frame_callback=self.get_frame_for_seek, # This will use the new pipeline
            send_state_callback=self.send_state_update_to_client,
            # update_canvas_dimensions_callback=self.frame_generator.update_canvas_dimensions, # OLD
            update_canvas_dimensions_callback=self.handle_update_canvas_dimensions, # NEW
            refresh_timeline_from_db_callback=self.refresh_timeline_from_database
        )
        
        # Pass the message handling callback to the WebSocketServer
        self.ws_server = websocket_server.WebSocketServer(
            port=args.ws_port,
            host=args.host,
            message_handler_callback=self.message_handler_instance.handle_message
        )

    def refresh_timeline_from_database(self):
        """Refresh timeline data directly from database and update playback controller"""
        logger.info("Refreshing timeline from database")
        
        # Refresh the timeline from database
        self.timeline_manager.refresh_from_database()
        
        # Update playback controller with new timeline parameters
        timeline_manager_state = self.timeline_manager.get_timeline_state()
        self.playback_controller.set_timeline_params(
            timeline_manager_state["frame_rate"],
            timeline_manager_state["total_frames"]
        )
        
        # Also update the TimelineStateService with the refreshed data
        self.timeline_state_service.update_timeline_data(
            videos=timeline_manager_state["videos"],
            total_frames=timeline_manager_state["total_frames"]
            # Canvas dimensions are handled separately
        )
        logger.info("Timeline refreshed from database and TimelineStateService updated.")

    def handle_update_canvas_dimensions(self, width: int, height: int):
        """Handles updates to canvas dimensions and informs the relevant service."""
        logger.debug(f"MainServer: Handling update canvas dimensions: {width}x{height}")
        changed = self.timeline_state_service.update_canvas_dimensions(width, height)
        if changed:
            # If dimensions change, the pipeline's final frame cache relying on
            # timeline_state_hash (which includes canvas dimensions) will naturally
            # use new keys. We might also consider explicitly clearing certain caches
            # if there are intermediate caches that don't automatically invalidate.
            # For now, TimelineStateService.get_hashable_timeline_state() includes
            # canvas dimensions, so the FramePipelineService's main cache key will change.
            logger.info(f"Canvas dimensions updated in TimelineStateService to {width}x{height}.")
            # Potentially, if playback is active, send a new frame or trigger UI update.
            # For now, just updating the state service is the core responsibility here.

    def get_frame_for_playback(self, frame_index: int) -> Optional[bytes]:
        """
        Wrapper to get a frame using the new FramePipelineService.
        Ensures TimelineStateService is updated before fetching.
        """
        # Ensure TimelineStateService has the latest from TimelineManager
        current_timeline_manager_state = self.timeline_manager.get_timeline_state()
        self.timeline_state_service.update_timeline_data(
            videos=current_timeline_manager_state["videos"],
            total_frames=current_timeline_manager_state["total_frames"]
            # Canvas dimensions are updated via handle_update_canvas_dimensions
        )
        
        # FramePipelineService uses the state from TimelineStateService internally
        return self.frame_pipeline_service.get_encoded_frame(frame_index)

    async def send_frame_to_all_clients(self, frame_data: str):
        """Wrapper to send frame data via WebSocket server"""
        await self.ws_server.send_frame_to_all(frame_data)

    def handle_update_timeline(self, video_data: List[Dict]):
        """Handle timeline updates and propagate changes to TimelineManager and TimelineStateService"""
        self.timeline_manager.handle_message_updates(video_data)
        
        # Get the updated state from TimelineManager
        updated_timeline_manager_state = self.timeline_manager.get_timeline_state()
        
        # Push this updated state to TimelineStateService
        self.timeline_state_service.update_timeline_data(
            videos=updated_timeline_manager_state["videos"],
            total_frames=updated_timeline_manager_state["total_frames"]
            # Canvas dimensions are handled separately by handle_update_canvas_dimensions
        )
        logger.info("Timeline data updated in TimelineStateService via handle_update_timeline.")

        # Update playback controller with new timeline parameters
        self.playback_controller.set_timeline_params(
            updated_timeline_manager_state["frame_rate"],
            updated_timeline_manager_state["total_frames"]
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
        logger.info(f"Starting FlipEdit Video Stream Server with Database Integration")
        logger.info(f"WebSocket server on port {self.args.ws_port}")
        logger.info(f"HTTP API server on port {self.args.http_port}")
        
        # Create and start the Flask preview server in a separate thread
        # TODO: Update preview_server to use the new FramePipelineService or TimelineStateService
        preview_app = preview_server.create_preview_server(
            # self.frame_generator, # OLD
            self.frame_pipeline_service, # NEW - or pass specific services it needs
            self.timeline_manager, # TimelineManager might still be useful for HTTP endpoints
            self.timeline_state_service # Pass this too, as it holds current state
        )
        # Run Flask in a daemon thread so it exits when the main thread exits
        preview_server_port = self.args.http_port
        logger.info(f"Starting Preview HTTP server on port {preview_server_port}")
        http_thread = threading.Thread(
            target=preview_app.run_server,
            kwargs={'host': self.args.host, 'port': preview_server_port},
            daemon=True
        )
        http_thread.start()
        
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
        
        # Close database connections
        if self.db_manager:
            self.db_manager.close()
            logger.info("Database connections closed")
        
    def perform_cleanup(self):
        """Perform cleanup tasks after servers have stopped."""
        if logger:
             logger.info("Performing cleanup...")
        # self.frame_generator.cleanup() # OLD
        self.frame_pipeline_service.clear_all_caches() # NEW
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