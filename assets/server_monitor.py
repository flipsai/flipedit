#!/usr/bin/env python3
import requests
import time
import sys
import os
from datetime import datetime

# Configuration
HEALTH_CHECK_URL = 'http://localhost:8081/health'
TIMELINE_DEBUG_URL = 'http://localhost:8081/debug/timeline'
CHECK_INTERVAL = 3  # seconds

def clear_screen():
    """Clear the terminal screen."""
    os.system('cls' if os.name == 'nt' else 'clear')

def format_timestamp():
    """Format the current timestamp."""
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def check_server_health():
    """Check server health and return stats."""
    try:
        response = requests.get(HEALTH_CHECK_URL, timeout=2)
        if response.status_code == 200:
            return response.json()
        print(f"Error: Server health check failed with status code: {response.status_code}")
        return None
    except requests.RequestException as e:
        print(f"Error: Server health check failed: {e}")
        return None

def get_timeline_debug():
    """Get timeline debug information."""
    try:
        response = requests.get(TIMELINE_DEBUG_URL, timeout=5)
        if response.status_code == 200:
            return response.json()
        print(f"Error: Timeline debug failed with status code: {response.status_code}")
        return None
    except requests.RequestException as e:
        print(f"Error: Timeline debug request failed: {e}")
        return None

def display_server_stats():
    """Display server statistics."""
    clear_screen()
    print("\n=== FlipEdit Preview Server Monitor ===")
    print(f"Time: {format_timestamp()}\n")
    
    # Check health and get basic stats
    health_stats = check_server_health()
    if health_stats:
        print("=== Server Status ===")
        print(f"Status: {health_stats.get('status', 'unknown')}")
        print(f"Active Requests: {health_stats.get('active_requests', 0)}")
        print(f"Queue Size: {health_stats.get('queue_size', 0)}")
        print(f"Max Concurrent: {health_stats.get('max_concurrent', 0)}")
        
        # Visual queue indicator
        queue_size = health_stats.get('queue_size', 0)
        max_bar = 20
        bar_length = min(queue_size, max_bar)
        bar = '█' * bar_length + '░' * (max_bar - bar_length)
        print(f"Queue: [{bar}] {queue_size}")
        
        print("")
    else:
        print("Server health check failed - server may be down\n")
        return
    
    # Get detailed timeline debug info
    timeline_info = get_timeline_debug()
    if timeline_info:
        print("=== Timeline Info ===")
        print(f"Total Frames: {timeline_info.get('total_frames', 0)}")
        print(f"Frame Rate: {timeline_info.get('frame_rate', 0)}")
        print(f"Clips Count: {timeline_info.get('clips_count', 0)}")
        
        # Display queue stats if available
        queue_stats = timeline_info.get('queue_stats', {})
        if queue_stats:
            print("\n=== Queue Stats ===")
            print(f"Queue Size: {queue_stats.get('queue_size', 0)}")
            print(f"Active Requests: {queue_stats.get('active_requests', 0)}")
    
    print("\nPress Ctrl+C to exit")

def main():
    """Main function to monitor server."""
    try:
        while True:
            display_server_stats()
            time.sleep(CHECK_INTERVAL)
    except KeyboardInterrupt:
        print("\nExiting server monitor...")
    except Exception as e:
        print(f"Error in monitor: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main() 