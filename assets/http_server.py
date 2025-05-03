#!/usr/bin/env python3
import http.server
import urllib.parse
import json
import logging
import threading

import media_utils

logger = logging.getLogger('video_stream_server')

class HTTPRequestHandler(http.server.BaseHTTPRequestHandler):
    """HTTP request handler for the API endpoints."""
    
    def do_GET(self):
        """Handle GET requests."""
        try:
            # Parse the URL
            parsed_url = urllib.parse.urlparse(self.path)
            path = parsed_url.path
            
            # Handle media duration endpoint
            if path.startswith('/api/duration'):
                query_params = urllib.parse.parse_qs(parsed_url.query)
                
                # Check if path parameter is provided
                if 'path' not in query_params:
                    self._send_error(400, "Missing 'path' parameter")
                    return
                
                file_path = query_params['path'][0]
                logger.info(f"HTTP API: Getting duration for: {file_path}")
                
                # Get media duration
                duration = media_utils.get_media_duration(file_path)
                
                # Return duration as JSON
                response = json.dumps({"duration_ms": duration})
                self._send_response(200, response)
                
            # Handle media info endpoint (both duration and dimensions)
            elif path.startswith('/api/mediainfo'):
                query_params = urllib.parse.parse_qs(parsed_url.query)
                
                # Check if path parameter is provided
                if 'path' not in query_params:
                    self._send_error(400, "Missing 'path' parameter")
                    return
                
                file_path = query_params['path'][0]
                logger.info(f"HTTP API: Getting media info for: {file_path}")
                
                # Get media info
                media_info = media_utils.get_media_info(file_path)
                
                # Return media info as JSON
                response = json.dumps(media_info)
                self._send_response(200, response)
                
            else:
                self._send_error(404, "Endpoint not found")
                
        except Exception as e:
            logger.error(f"Error handling HTTP request: {e}")
            self._send_error(500, f"Internal server error: {str(e)}")
    
    def _send_response(self, status_code, message):
        """Send a JSON response."""
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')  # CORS header for cross-origin requests
        self.end_headers()
        self.wfile.write(message.encode('utf-8'))
    
    def _send_error(self, status_code, message):
        """Send an error response."""
        response = json.dumps({"error": message})
        self._send_response(status_code, response)

def run_http_server(host="0.0.0.0", port=8081):
    """Run an HTTP server for API endpoints."""
    # Create and start the HTTP server in a separate thread
    server = http.server.HTTPServer((host, port), HTTPRequestHandler)
    logger.info(f"Starting HTTP API server on http://{host}:{port}")
    
    # Run the server in a separate thread
    server_thread = threading.Thread(target=server.serve_forever)
    server_thread.daemon = True  # Thread will exit when main thread exits
    server_thread.start()
    
    # Return the server instance so it can be shut down if needed
    return server