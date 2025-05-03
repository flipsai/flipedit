#!/usr/bin/env python3
import json
import logging
import base64
from typing import Callable, Dict, List, Any, Optional

logger = logging.getLogger('video_stream_server')

class MessageHandler:
    def __init__(
        self,
        update_timeline_callback: Callable[[List[Dict]], None],
        start_playback_callback: Callable[[], None],
        stop_playback_callback: Callable[[], None],
        seek_callback: Callable[[int], int],
        get_frame_callback: Callable[[int], Optional[bytes]],
        send_state_callback: Callable[[Any, bool], None]
    ):
        """
        Initialize the message handler with callback functions
        
        Args:
            update_timeline_callback: Function to update timeline with clip data
            start_playback_callback: Function to start playback
            stop_playback_callback: Function to stop playback
            seek_callback: Function to seek to a specific frame
            get_frame_callback: Function to get a frame at a specific index
            send_state_callback: Function to send playback state to a client
        """
        self.update_timeline = update_timeline_callback
        self.start_playback = start_playback_callback
        self.stop_playback = stop_playback_callback
        self.seek = seek_callback
        self.get_frame = get_frame_callback
        self.send_state_update = send_state_callback
    
    async def handle_message(self, websocket, message: str):
        """Handle incoming messages from clients."""
        try:
            if message == "play":
                await self.start_playback()
                # Send state update to confirm play state
                await self.send_state_update(websocket, True)
                
            elif message == "pause":
                await self.stop_playback()
                # Send state update to confirm pause state
                await self.send_state_update(websocket, False)
                
            elif message.startswith("seek:"):
                # Format: seek:123 (frame number)
                try:
                    frame = int(message.split(':')[1])
                    
                    # Seek to the requested frame
                    actual_frame = self.seek(frame)
                    
                    # Always stop playback during manual seeking to prevent auto-play
                    was_playing = False  # Store playback state if needed for restoration
                    await self.stop_playback()
                    
                    # Send the current frame immediately
                    frame_bytes = self.get_frame(actual_frame)
                    if frame_bytes:
                        encoded_frame = base64.b64encode(frame_bytes).decode('utf-8')
                        await websocket.send(encoded_frame)
                    
                    # Confirm to client that we're in paused state after seeking
                    await self.send_state_update(websocket, False)
                    
                except ValueError:
                    logger.error(f"Invalid frame number in seek command: {message}")
                    
            elif message.startswith('{"type":"clips"'): # Check for the new JSON format
                try:
                    data = json.loads(message)
                    if data.get('type') == 'clips':
                        video_data = data.get('data', [])
                        logger.info(f"Received 'clips' message with {len(video_data)} clips.")
                        # Log the received raw data (truncated)
                        truncated_data = str(video_data)[:500]
                        logger.debug(f"Raw clips data received (truncated): {truncated_data}")
                        self.update_timeline(video_data)
                    else:
                        logger.warning(f"Received JSON message with unknown type: {data.get('type')}")
                except json.JSONDecodeError as e:
                    logger.error(f"Invalid JSON received: {message[:200]}... Error: {e}")
                except Exception as e:
                    logger.error(f"Error processing 'clips' message: {e}")
                    
            elif message.startswith("videos:"): # Keep old format for compatibility
                # Format: videos:<json_data> - This path might be deprecated now
                logger.warning("Received message in deprecated 'videos:' format. Processing anyway.")
                json_str = message[7:]  # Remove "videos:" prefix
                try:
                    video_data = json.loads(json_str)
                    self.update_timeline(video_data)
                except json.JSONDecodeError:
                    logger.error(f"Invalid JSON in videos message: {json_str}")
                    
            else:
                logger.warning(f"Unknown command received: {message[:100]}...") # Log only the start of unknown messages
                
        except Exception as e:
            logger.error(f"Error handling message: {e}")