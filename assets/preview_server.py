# assets/preview_server.py
from flask import Flask, Response, jsonify, abort
import logging
import traceback

# Assume FrameGenerator and TimelineManager are passed in or accessible
# We'll refine how these are accessed when integrating with main.py

logger = logging.getLogger('preview_server')

def create_preview_server(frame_generator, timeline_manager):
    """Creates the Flask application instance."""
    app = Flask(__name__)
    app.config['FRAME_GENERATOR'] = frame_generator
    app.config['TIMELINE_MANAGER'] = timeline_manager

    @app.route('/get_frame/<int:frame_index>', methods=['GET'])
    def get_frame_route(frame_index):
        """
        Endpoint to get a specific frame based on the timeline state.
        """
        try:
            logger.info(f"Received HTTP request for frame: {frame_index}")
            
            current_frame_generator = app.config['FRAME_GENERATOR']
            current_timeline_manager = app.config['TIMELINE_MANAGER']

            # Always refresh from database to ensure up-to-date clip dimensions
            logger.info("HTTP endpoint: Force refreshing timeline from database")
            current_timeline_manager.refresh_from_database()
            logger.info("HTTP endpoint: Timeline refreshed from database")

            # Get current timeline state from TimelineManager
            timeline_state = current_timeline_manager.get_timeline_state()
            if not timeline_state:
                logger.error("TimelineManager did not provide timeline state.")
                abort(500, description="Could not retrieve timeline state.")

            current_videos = timeline_state.get("videos")
            total_frames = timeline_state.get("total_frames")

            # Check if we got the necessary data
            if current_videos is None or total_frames is None:
                 logger.error(f"Timeline state missing required keys. State: {timeline_state}")
                 abort(500, description="Incomplete timeline data.")

            # Log clip dimensions for debugging
            logger.info(f"HTTP endpoint: Processing {len(current_videos)} clips")
            for i, video in enumerate(current_videos):
                start_ms = video.get('startTimeOnTrackMs')
                end_ms = video.get('endTimeOnTrackMs')
                src_start = video.get('startTimeInSourceMs')
                src_end = video.get('endTimeInSourceMs')
                logger.info(f"HTTP endpoint: Clip[{i}] track time: {start_ms}-{end_ms}ms, source time: {src_start}-{src_end}ms")

            logger.debug(f"Generating frame {frame_index} with {len(current_videos)} clips, total_frames={total_frames}")

            # Generate the frame using FrameGenerator
            frame_bytes = current_frame_generator.get_frame(frame_index, current_videos, total_frames)

            if frame_bytes:
                logger.info(f"HTTP endpoint: Successfully generated frame {frame_index}")
                # Return the frame as JPEG image
                return Response(frame_bytes, mimetype='image/jpeg')
            else:
                logger.warning(f"HTTP endpoint: FrameGenerator returned None for frame {frame_index}")
                # Return a 404 or a blank image? Let's return 404 for now.
                abort(404, description=f"Frame {frame_index} could not be generated.")

        except Exception as e:
            logger.error(f"HTTP endpoint: Error generating frame {frame_index}: {e}")
            logger.error(traceback.format_exc()) # Log the full traceback
            abort(500, description="Internal server error generating frame.")
            
    @app.route('/health', methods=['GET'])
    def health_check():
        """Basic health check endpoint."""
        return jsonify({"status": "ok"})
        
    @app.route('/debug/timeline', methods=['GET'])
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
                "clips": clips_info
            })
            
        except Exception as e:
            logger.error(f"Error in debug timeline endpoint: {e}")
            logger.error(traceback.format_exc())
            return jsonify({"error": str(e)}), 500

    return app
