# FlipEdit Preview Server Reliability Notes

## Server Stability Improvements

We've added several reliability enhancements to the preview server to prevent connection issues when handling many requests:

1. **Request Queuing System**: The server now queues requests when it's busy instead of dropping connections
2. **Connection Limiting**: Limits the number of simultaneous connections to prevent overload
3. **Worker Thread Pool**: Processes queued requests in the background
4. **Health Monitoring**: Provides detailed health information through the API

## Monitoring Scripts

Several monitoring scripts are provided to help maintain server reliability:

### 1. Server Monitor (server_monitor.py)

This script displays real-time information about the server's health, request queue, and processing stats.

To use:
```bash
# Make it executable (only needed once)
chmod +x assets/server_monitor.py

# Install required packages
pip install requests

# Run the monitoring tool
./assets/server_monitor.py
```

### 2. Server Watchdog (server_watchdog.py)

This is an advanced Python script that monitors the server's health and restarts it if it becomes unresponsive.

To use:
```bash
# Make it executable (only needed once)
chmod +x assets/server_watchdog.py

# Install required packages
pip install requests

# Run the monitoring script
./assets/server_watchdog.py
```

### 3. Simple Restart Script (restart_server.sh)

This is a simple shell script that will automatically restart the server if it crashes.

To use:
```bash
# Make it executable (only needed once)
chmod +x assets/restart_server.sh

# Run the monitoring script
./assets/restart_server.sh
```

## Client-Side Optimizations

The following optimizations have been made to the client side to reduce server load:

1. **Request throttling**: Prevents sending too many requests in a short time
2. **Connection pooling**: Reuses connections to reduce overhead
3. **Request queuing**: Ensures requests are processed in order and with proper pacing
4. **Failure handling**: Detects when the server is having issues and backs off

## Server Configuration Options

You can adjust the following server parameters in `assets/preview_server.py` if needed:

- `MAX_CONCURRENT_REQUESTS` (default: 2): Maximum number of concurrent requests to process
- `request_queue.maxsize` (default: 20): Maximum queue size before rejecting new requests
- `server.max_connections` (default: 15): Maximum number of TCP connections to accept

## If Problems Persist

If you continue to experience issues, consider:

1. **Increase throttling delay**: Edit `UpdateRequestTracker.shouldThrottle()` in `lib/viewmodels/commands/update_clip_preview_rect_command.dart` to use a longer delay
2. **Increase server queue size**: Edit `request_queue = queue.Queue(maxsize=20)` in `assets/preview_server.py` to use a larger value
3. **Decrease MAX_CONCURRENT_REQUESTS**: Try reducing to 1 if the server is getting overwhelmed

## Troubleshooting

If you see "Connection closed before full header was received" errors:

1. Check if the server is running and responsive
2. Look at the queue stats using the server monitor
3. Verify if requests are being throttled properly on the client side
4. Consider decreasing the request rate by increasing delays between requests

## Advanced: Profiling the Python Server

If you want to identify performance bottlenecks in the Python server:

```bash
# Install profiling tools
pip install py-spy

# Profile the running server 
sudo py-spy record -o profile.svg --pid <SERVER_PID>
``` 