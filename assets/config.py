#!/usr/bin/env python3
import argparse
import logging
import sys

def parse_args():
    """Parse command-line arguments for the server"""
    parser = argparse.ArgumentParser(description="FlipEdit Video Stream Server")
    parser.add_argument('--ws-port', type=int, default=8080, help='WebSocket server port')
    parser.add_argument('--http-port', type=int, default=8081, help='HTTP server port')
    parser.add_argument('--host', type=str, default='0.0.0.0', help='Host to bind to')
    parser.add_argument('--debug', action='store_true', help='Enable debug logging')
    return parser.parse_args()

def configure_logging(args=None):
    """Configure the logging system based on arguments"""
    # Configure basic logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.StreamHandler(sys.stdout)
        ]
    )
    
    # Get the main logger
    logger = logging.getLogger('video_stream_server')
    
    # Set debug level if requested
    if args and args.debug:
        logger.setLevel(logging.DEBUG)
        logger.debug("Debug logging enabled")
    
    return logger

# Default configuration values
DEFAULT_FRAME_RATE = 30
DEFAULT_TOTAL_FRAMES = 600  # 20 seconds at 30fps
DEFAULT_WS_PORT = 8080
DEFAULT_HTTP_PORT = 8081
DEFAULT_HOST = "0.0.0.0"