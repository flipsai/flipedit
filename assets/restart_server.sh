#!/bin/bash

# Auto-restart script for the FlipEdit preview server
# This script will restart the server if it crashes

echo "Starting FlipEdit preview server auto-restart script"
echo "Press Ctrl+C to exit"

while true; do
  # Print a timestamp
  echo ""
  echo "$(date): Starting preview server..."
  
  # Start the server 
  python3 assets/main.py
  
  # If we get here, the server has exited
  EXIT_CODE=$?
  
  if [ $EXIT_CODE -eq 0 ]; then
    echo "$(date): Server exited normally. Restarting in 1 second..."
  else
    echo "$(date): Server crashed with exit code $EXIT_CODE. Restarting in 2 seconds..."
    # Wait longer after a crash
    sleep 2
  fi
  
  # Wait a moment before restarting to avoid rapid restart loops
  sleep 1
done 