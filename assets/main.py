#!/usr/bin/env python3
import asyncio
import signal
import logging
from typing import Optional

# Import the refactored modules
import config
import timeline_manager as timeline_manager_module

# Import new video services
from video_services.timeline_state_service import TimelineStateService
from video_services.video_source_service import VideoSourceService
from video_services.frame_transform_service import FrameTransformService
from video_services.compositing_service import CompositingService
from video_services.encoding_service import EncodingService
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
        # self.intermediate_frame_cache_service = FrameCacheService(max_cache_entries=120) # Removed
        self.frame_transform_service = FrameTransformService()
        self.compositing_service = CompositingService()
        self.encoding_service = EncodingService()
        
        self.frame_pipeline_service = FramePipelineService(
            timeline_state_service=self.timeline_state_service,
            video_source_service=self.video_source_service,
            frame_transform_service=self.frame_transform_service,
            compositing_service=self.compositing_service,
            encoding_service=self.encoding_service
            # intermediate_frame_cache_service argument removed
        )
        
        # Set debug verbosity to reduce excessive logging
        self.frame_pipeline_service.set_debug_verbosity(False)
        self.frame_transform_service.set_debug_verbosity(False)
        
        # Enable verbose debug only if explicitly requested
        if hasattr(self.args, 'verbose_debug') and self.args.verbose_debug:
            logger.info("Enabling verbose debug logging for video services")
            self.frame_pipeline_service.set_debug_verbosity(True)
            self.frame_transform_service.set_debug_verbosity(True)
            
        # --- End new video services instantiation ---
        
        # self.frame_generator = frame_generator.FrameGenerator() # OLD
        
        # PlaybackController and MessageHandler removed.
        # Their functionalities will be handled by HTTP endpoints in preview_server.py
        
        # self.ws_server instantiation removed

    # dummy_send_frame_callback removed
    # dummy_send_state_callback removed

    def refresh_timeline_from_database(self):
        """Refresh timeline data directly from database."""
        logger.info("Refreshing timeline from database")
        
        # Refresh the timeline from database
        self.timeline_manager.refresh_from_database()
        
        # Get timeline state
        timeline_manager_state = self.timeline_manager.get_timeline_state()
        
        # Also update the TimelineStateService with the refreshed data
        self.timeline_state_service.update_timeline_data(
            videos=timeline_manager_state["videos"],
            total_frames=timeline_manager_state["total_frames"],
            frame_rate=timeline_manager_state.get("frame_rate", 30.0)  # Use default 30.0 if not available
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

    # get_frame_for_playback removed (will be handled by HTTP endpoint)
    # async def send_frame_to_all_clients removed
    # handle_update_timeline removed (will be handled by HTTP endpoint)
    # handle_seek removed (will be handled by HTTP endpoint)
    # get_frame_for_seek removed (will be handled by HTTP endpoint)

    def setup_signal_handlers(self):
        """Set up signal handlers for graceful shutdown."""
        # For a non-async main loop, signal handling might need adjustment.
        # For now, let's assume the HTTP server thread handles its own termination.
        # If the main thread just starts the HTTP server and exits, this might not be needed here.
        # However, if we want the main thread to wait, we'll need a way to signal it.
        try:
            loop = asyncio.get_running_loop()
            for sig in (signal.SIGINT, signal.SIGTERM):
                loop.add_signal_handler(sig, self.shutdown)
            logger.info("Signal handlers registered for SIGINT and SIGTERM (if asyncio loop is primary).")
        except RuntimeError:
            logger.info("No asyncio running loop for signal handlers, using direct signal.signal.")
            signal.signal(signal.SIGINT, self.signal_handler_sync)
            signal.signal(signal.SIGTERM, self.signal_handler_sync)


    def signal_handler_sync(self, signum, frame):
        """Synchronous signal handler."""
        logger.info(f"Signal {signum} received. Initiating shutdown...")
        self.shutdown()
        # In a purely threaded model, we might need a more robust way to stop the http_thread.
        # For Flask's dev server, KeyboardInterrupt on the main thread usually stops it.
        # If running with a production server like Gunicorn, it handles signals.
        # For now, this will call shutdown, and the daemon thread should exit with the main.
        # Consider raising SystemExit to ensure main thread termination.
        raise SystemExit("Shutdown initiated by signal.")


    async def run(self): # Keep async for now, but WebSocket part is removed
        """Run the HTTP streaming server."""
        logger.info(f"Starting FlipEdit Video Streaming Server")
        logger.info(f"HTTP Stream server on port {self.args.http_port}")
        
        preview_app = preview_server.create_preview_server(
            self.frame_pipeline_service,
            self.timeline_manager,
            self.timeline_state_service
        )
        
        # Use a different port to avoid conflicts
        preview_server_port = 8085  # Changed to 8085 to further avoid potential port conflicts
        logger.info(f"Starting Preview HTTP (streaming) server on port {preview_server_port}")
        
        # Run Flask server. For simplicity, directly in the main thread.
        # If main needs to do other async tasks, then threading is appropriate.
        # For a dedicated streaming server, running Flask directly is fine.
        self.setup_signal_handlers() # Setup signals before blocking call

        try:
            # Flask's app.run is blocking.
            preview_app.run_server(host=self.args.host, port=preview_server_port)
        except SystemExit:
            logger.info("SystemExit caught, proceeding with cleanup.")
        except KeyboardInterrupt:
            logger.info("KeyboardInterrupt caught, initiating shutdown.")
            self.shutdown()
        finally:
            self.perform_cleanup()


    def shutdown(self):
        """Initiate graceful shutdown of all components."""
        if logger: # Check if logger is initialized
            logger.info("Shutdown requested...")
        
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

def parse_args():
    """Parse command-line arguments with additional debug settings."""
    # Get the base argument parser from config.py
    parser = config.get_argument_parser() 
    
    # Add new arguments specific to main.py or for extended functionality
    # Make sure this is a parent parser if we want to share help messages, or create a new one and parse known args.
    # For simplicity here, we'll add to the existing one. Ensure add_help=False in get_argument_parser if conflicts arise.
    # Or, use a parent parser approach:
    # parent_parser = config.get_argument_parser()
    # parser = argparse.ArgumentParser(parents=[parent_parser]) # This handles help combination better.

    parser.add_argument('--verbose-debug', action='store_true',
                        help='Enable verbose debug logging for video services')
    # Add other main.py specific args here if needed
    
    args = parser.parse_args()
    return args

async def main():
    # Parse command-line arguments
    args = parse_args()
    
    # Create and run the main server application
    main_server = MainServer(args)
    await main_server.run()

if __name__ == "__main__":
    asyncio.run(main())