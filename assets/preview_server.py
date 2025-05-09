# assets/preview_server.py
from flask import Flask, Response, jsonify, abort, request
import logging
import traceback
import threading
import queue
import time
from functools import wraps

# Assume FrameGenerator and TimelineManager are passed in or accessible
# We'll refine how these are accessed when integrating with main.py

logger = logging.getLogger('preview_server')

# Global request queue and processor
request_queue = queue.Queue(maxsize=20)  # Limit queue size
request_processing_lock = threading.Lock()
MAX_CONCURRENT_REQUESTS = 2  # Maximum number of concurrent requests to process
active_requests = 0

def queue_request(timeout=10):
    """Decorator to queue incoming requests to avoid overloading the server."""
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            global active_requests
            
            # Check if request should be queued
            with request_processing_lock:
                if active_requests >= MAX_CONCURRENT_REQUESTS:
                    try:
                        logger.info(f"Queueing request: {request.path} (active: {active_requests})")
                        # Create a task for the queue
                        task = {
                            "func": f,
                            "args": args,
                            "kwargs": kwargs,
                            "result_queue": queue.Queue()
                        }
                        
                        # Try to put in queue with timeout to avoid blocking
                        try:
                            request_queue.put(task, block=True, timeout=timeout)
                        except queue.Full:
                            logger.error("Request queue full, rejecting request")
                            abort(503, description="Server too busy, try again later")
                        
                        # Wait for result with timeout
                        try:
                            result = task["result_queue"].get(block=True, timeout=timeout)
                            return result
                        except queue.Empty:
                            logger.error("Request processing timed out")
                            abort(504, description="Request processing timed out") 
                    except Exception as e:
                        logger.error(f"Error in request queue: {e}")
                        abort(500, description="Internal server error in request queue")
                
                # Process request directly if no queueing needed
                active_requests += 1
            
            try:
                return f(*args, **kwargs)
            except Exception as e:
                logger.error(f"Exception in request handler: {e}")
                logger.error(traceback.format_exc())
                abort(500, description=f"Internal server error: {str(e)}")
            finally:
                with request_processing_lock:
                    active_requests -= 1
        
        return decorated_function
    return decorator

# Start a worker thread to process queued requests
def process_request_queue():
    """Worker function to process queued requests."""
    global active_requests
    
    while True:
        try:
            # Get a task from the queue
            task = request_queue.get(block=True)
            
            # Wait until we can process the request
            can_process = False
            while not can_process:
                with request_processing_lock:
                    if active_requests < MAX_CONCURRENT_REQUESTS:
                        active_requests += 1
                        can_process = True
                
                if not can_process:
                    time.sleep(0.1)  # Wait a bit before checking again
            
            # Process the request
            try:
                result = task["func"](*task["args"], **task["kwargs"])
                task["result_queue"].put(result)
            except Exception as e:
                logger.error(f"Error processing queued request: {e}")
                logger.error(traceback.format_exc())
                task["result_queue"].put(jsonify({"error": str(e)}), 500)
            finally:
                with request_processing_lock:
                    active_requests -= 1
                
                request_queue.task_done()
        
        except Exception as e:
            logger.error(f"Error in request queue processor: {e}")
            logger.error(traceback.format_exc())
            time.sleep(1)

def create_preview_server(frame_pipeline_service, timeline_manager, timeline_state_service):
    """Creates the Flask application instance."""
    app = Flask(__name__)
    app.config['FRAME_PIPELINE_SERVICE'] = frame_pipeline_service 
    app.config['TIMELINE_MANAGER'] = timeline_manager 
    app.config['TIMELINE_STATE_SERVICE'] = timeline_state_service 
    app.config['LAST_TIMELINE_REFRESH_TIME'] = 0
    app.config['TIMELINE_REFRESH_INTERVAL'] = 1.0
    
    # Start the request queue processor thread
    queue_processor_thread = threading.Thread(
        target=process_request_queue,
        daemon=True
    )
    queue_processor_thread.start()

    @app.route('/get_frame/<int:frame_index>', methods=['GET'])
    @queue_request(timeout=15)
    def get_frame_route(frame_index):
        """
        Endpoint to get a specific frame based on the timeline state.
        """
        try:
            logger.info(f"Processing HTTP request for frame: {frame_index}")
            
            # Get new services from app.config
            current_pipeline_service = app.config['FRAME_PIPELINE_SERVICE']
            current_timeline_manager = app.config['TIMELINE_MANAGER'] # Still used for DB refresh
            current_timeline_state_service = app.config['TIMELINE_STATE_SERVICE']

            current_time = time.time()
            last_refresh_time = app.config['LAST_TIMELINE_REFRESH_TIME']
            refresh_interval = app.config['TIMELINE_REFRESH_INTERVAL']
            
            # Check if a refresh from DB is needed for this HTTP endpoint's perspective
            # The WebSocket path might have more up-to-date info in TimelineStateService already.
            # This refresh ensures this HTTP endpoint can also trigger DB reads if it's been a while.
            if current_time - last_refresh_time > refresh_interval:
                logger.info("HTTP endpoint: Refresh interval elapsed. Refreshing timeline from database.")
                current_timeline_manager.refresh_from_database()
                refreshed_manager_state = current_timeline_manager.get_timeline_state()
                
                if not refreshed_manager_state:
                    logger.error("TimelineManager did not provide timeline state after refresh.")
                    abort(500, description="Could not retrieve timeline state from TimelineManager.")
                
                # Update the shared TimelineStateService with this refreshed data
                current_timeline_state_service.update_timeline_data(
                    videos=refreshed_manager_state.get("videos", []),
                    total_frames=refreshed_manager_state.get("total_frames", 0)
                )
                # Note: Canvas dimensions are typically updated via WebSocket.
                # If HTTP needs to ensure default/latest, it could call:
                # current_timeline_state_service.update_canvas_dimensions(default_w, default_h)
                
                app.config['LAST_TIMELINE_REFRESH_TIME'] = current_time
                
                # Clear pipeline caches as timeline data has potentially changed significantly
                current_pipeline_service.clear_all_caches()
                logger.info("HTTP endpoint: Timeline refreshed from DB, TimelineStateService updated, and FramePipelineService caches cleared.")
            
            # FramePipelineService will use the (potentially just updated) TimelineStateService
            # for its source of truth regarding videos, total_frames, and canvas dimensions.
            logger.debug(f"HTTP endpoint: Requesting frame {frame_index} from FramePipelineService.")
            frame_bytes = current_pipeline_service.get_encoded_frame(frame_index)

            if frame_bytes:
                logger.info(f"HTTP endpoint: Successfully generated frame {frame_index}")
                # Return the frame as JPEG image
                return Response(frame_bytes, mimetype='image/jpeg')
            else:
                logger.warning(f"HTTP endpoint: FramePipelineService returned None for frame {frame_index}")
                # Return a 404 or a blank image? Let's return 404 for now.
                abort(404, description=f"Frame {frame_index} could not be generated.")

        except Exception as e:
            logger.error(f"HTTP endpoint: Error generating frame {frame_index}: {e}")
            logger.error(traceback.format_exc()) # Log the full traceback
            abort(500, description="Internal server error generating frame.")
            
    @app.route('/health', methods=['GET'])
    def health_check():
        """Basic health check endpoint."""
        # Include queue stats in health check
        return jsonify({
            "status": "ok",
            "queue_size": request_queue.qsize(),
            "active_requests": active_requests,
            "max_concurrent": MAX_CONCURRENT_REQUESTS
        })
        
    @app.route('/debug/timeline', methods=['GET'])
    @queue_request(timeout=10)  # Queue with a 10-second timeout
    def debug_timeline():
        """Debug endpoint to view the current timeline state."""
        try:
            current_timeline_manager = app.config['TIMELINE_MANAGER']
            
            # Refresh from database
            current_timeline_manager.refresh_from_database()
            
            # Get timeline state
            timeline_state = current_timeline_manager.get_timeline_state()
            if not timeline_state:
                return jsonify({"error": "No timeline state available"}), 500
                
            # Extract and format clips for debugging
            videos = timeline_state.get("videos", [])
            clips_info = []
            
            for i, video in enumerate(videos):
                clips_info.append({
                    "index": i,
                    "source_path": video.get("sourcePath"),
                    "track_time_ms": {
                        "start": video.get("startTimeOnTrackMs"),
                        "end": video.get("endTimeOnTrackMs"),
                        "duration": video.get("endTimeOnTrackMs") - video.get("startTimeOnTrackMs")
                    },
                    "source_time_ms": {
                        "start": video.get("startTimeInSourceMs"),
                        "end": video.get("endTimeInSourceMs"),
                        "duration": video.get("endTimeInSourceMs") - video.get("startTimeInSourceMs")
                    }
                })
                
            return jsonify({
                "total_frames": timeline_state.get("total_frames"),
                "frame_rate": timeline_state.get("frame_rate"),
                "clips_count": len(videos),
                "clips": clips_info,
                "queue_stats": {
                    "queue_size": request_queue.qsize(),
                    "active_requests": active_requests
                }
            })
            
        except Exception as e:
            logger.error(f"Error in debug timeline endpoint: {e}")
            logger.error(traceback.format_exc())
            return jsonify({"error": str(e)}), 500

    # Simplified run method that uses Flask's built-in server
    def run_server(host='0.0.0.0', port=8081):
        """Run the Flask app with the standard development server."""
        # Configure Flask to handle request timeout issues 
        logger.info(f"Starting standard Flask server on {host}:{port}")
        
        try:
            # Use Flask's built-in server with reasonable settings for this use case
            app.run(
                host=host,
                port=port,
                threaded=True,    # Enable threading for concurrent requests
                debug=False,      # Disable debug mode in production
                use_reloader=False # Disable auto-reloading
            )
        except KeyboardInterrupt:
            logger.info("Server shutting down due to keyboard interrupt")
        except Exception as e:
            logger.error(f"Server error: {e}")
            logger.error(traceback.format_exc())
            # Wait a moment before raising to allow logging to complete
            time.sleep(1)
            raise
    
    # Add our custom run method to the app
    app.run_server = run_server

    return app
