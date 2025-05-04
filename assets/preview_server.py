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
            logger.info(f"Received request for frame: {frame_index}")
            
            current_frame_generator = app.config['FRAME_GENERATOR']
            current_timeline_manager = app.config['TIMELINE_MANAGER']

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

            logger.debug(f"Generating frame {frame_index} with {len(current_videos)} clips, total_frames={total_frames}")

            # Generate the frame using FrameGenerator
            frame_bytes = current_frame_generator.get_frame(frame_index, current_videos, total_frames)

            if frame_bytes:
                logger.info(f"Successfully generated frame {frame_index}")
                # Return the frame as JPEG image
                return Response(frame_bytes, mimetype='image/jpeg')
            else:
                logger.warning(f"FrameGenerator returned None for frame {frame_index}")
                # Return a 404 or a blank image? Let's return 404 for now.
                abort(404, description=f"Frame {frame_index} could not be generated.")

        except Exception as e:
            logger.error(f"Error generating frame {frame_index}: {e}")
            logger.error(traceback.format_exc()) # Log the full traceback
            abort(500, description="Internal server error generating frame.")
            
    @app.route('/health', methods=['GET'])
    def health_check():
        """Basic health check endpoint."""
        return jsonify({"status": "ok"})

    return app
