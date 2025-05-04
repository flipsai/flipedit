#!/usr/bin/env python3
import subprocess
import time
import signal
import sys
import os
import logging
import requests
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger('server_watchdog')

# Configuration
SERVER_SCRIPT = os.path.join(os.path.dirname(__file__), 'main.py')
HEALTH_CHECK_URL = 'http://localhost:8081/health'
HEALTH_CHECK_INTERVAL = 5  # seconds
MAX_RESTART_ATTEMPTS = 5
RESTART_BACKOFF = 5  # seconds

# Global variables
server_process = None
restart_attempts = 0

def start_server():
    """Start the preview server process."""
    global server_process
    logger.info(f"Starting server: python3 {SERVER_SCRIPT}")
    server_process = subprocess.Popen(
        ['python3', SERVER_SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True
    )
    logger.info(f"Server started with PID: {server_process.pid}")
    return server_process

def check_server_health():
    """Check if the server is responding to health checks."""
    try:
        response = requests.get(HEALTH_CHECK_URL, timeout=2)
        if response.status_code == 200:
            return True
        logger.warning(f"Server health check failed with status code: {response.status_code}")
        return False
    except requests.RequestException as e:
        logger.warning(f"Server health check failed: {e}")
        return False

def restart_server():
    """Restart the server after killing the current process."""
    global server_process, restart_attempts
    
    restart_attempts += 1
    
    if restart_attempts > MAX_RESTART_ATTEMPTS:
        logger.error(f"Maximum restart attempts ({MAX_RESTART_ATTEMPTS}) reached. Exiting.")
        sys.exit(1)
    
    # Kill existing process if it exists
    if server_process:
        logger.info(f"Stopping server process (PID: {server_process.pid})")
        try:
            server_process.terminate()
            server_process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            logger.warning("Server not responding to terminate signal, sending KILL")
            server_process.kill()
        except Exception as e:
            logger.error(f"Error stopping server: {e}")
    
    # Wait before restart with exponential backoff
    backoff_time = RESTART_BACKOFF * restart_attempts
    logger.info(f"Waiting {backoff_time} seconds before restart attempt {restart_attempts}")
    time.sleep(backoff_time)
    
    # Start the server
    start_server()

def signal_handler(sig, frame):
    """Handle Ctrl+C and other signals to properly shut down."""
    logger.info("Shutdown signal received")
    if server_process:
        logger.info("Stopping server process before exit")
        server_process.terminate()
        try:
            server_process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server_process.kill()
    sys.exit(0)

def main():
    """Main watchdog function."""
    # Set up signal handlers
    signal.signal(signal.SIGINT, signal_handler)  # Ctrl+C
    signal.signal(signal.SIGTERM, signal_handler)  # Termination signal
    
    # Start the server initially
    start_server()
    
    # Wait a bit for the server to start
    time.sleep(3)
    
    # Reset restart attempts after initial start
    global restart_attempts
    restart_attempts = 0
    
    # Main monitoring loop
    while True:
        try:
            # Check if process is still running
            if server_process.poll() is not None:
                logger.warning(f"Server process exited with code: {server_process.returncode}")
                restart_server()
                continue
            
            # Check server health
            if not check_server_health():
                logger.warning("Server health check failed")
                restart_server()
                continue
            
            # If we reach here, server is healthy, reset restart attempts
            if restart_attempts > 0:
                logger.info("Server is healthy again, resetting restart counter")
                restart_attempts = 0
            
            # Wait for next check
            time.sleep(HEALTH_CHECK_INTERVAL)
            
        except Exception as e:
            logger.error(f"Error in watchdog loop: {e}")
            time.sleep(HEALTH_CHECK_INTERVAL)

if __name__ == "__main__":
    logger.info("Server watchdog started")
    main() 