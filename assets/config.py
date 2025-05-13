#!/usr/bin/env python3
import argparse
import logging
import sys

def get_argument_parser():
    """Creates and returns the ArgumentParser for base server arguments."""
    parser = argparse.ArgumentParser(description="FlipEdit Video Stream Server", add_help=False)
    parser.add_argument('--ws-port', type=int, default=DEFAULT_WS_PORT, help='WebSocket server port')
    parser.add_argument('--http-port', type=int, default=DEFAULT_HTTP_PORT, help='HTTP server port')
    parser.add_argument('--host', type=str, default=DEFAULT_HOST, help='Host to bind to')
    parser.add_argument('--debug', action='store_true', help='Enable debug logging for base server')
    return parser

def parse_args():
    """Parse command-line arguments for the server using the base parser."""
    parser = get_argument_parser()
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