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
        send_state_callback: Callable[[Any, bool], None],
        update_canvas_dimensions_callback: Callable[[int, int], None] = None,
        refresh_timeline_from_db_callback: Callable[[], None] = None 
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
            update_canvas_dimensions_callback: Function to update canvas dimensions
            refresh_timeline_from_db_callback: Function to refresh timeline data from database
        """
        self.update_timeline = update_timeline_callback
        self.start_playback = start_playback_callback
        self.stop_playback = stop_playback_callback
        self.seek = seek_callback
        self.get_frame = get_frame_callback
        self.send_state_update = send_state_callback
        self.update_canvas_dimensions = update_canvas_dimensions_callback
        self.refresh_timeline_from_db = refresh_timeline_from_db_callback
    
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
            
            # Add handler for canvas_dimensions messages
            elif message.startswith('{"type":"canvas_dimensions"'):
                try:
                    data = json.loads(message)
                    if data.get('type') == 'canvas_dimensions' and self.update_canvas_dimensions:
                        payload = data.get('payload', {})
                        width = payload.get('width')
                        height = payload.get('height')
                        if width and height:
                            logger.info(f"Received canvas dimensions: {width}x{height}")
                            self.update_canvas_dimensions(width, height)
                            
                            # Force a frame refresh by seeking to the current frame
                            current_frame = self.seek(self.seek(0))  # Get current frame index
                            frame_bytes = self.get_frame(current_frame)
                            if frame_bytes and websocket:
                                # Send the refreshed frame with updated dimensions
                                encoded_frame = base64.b64encode(frame_bytes).decode('utf-8')
                                await websocket.send(encoded_frame)
                                logger.info(f"Refreshed frame with new dimensions: {width}x{height}")
                        else:
                            logger.warning(f"Invalid canvas dimensions in message: {payload}")
                except json.JSONDecodeError as e:
                    logger.error(f"Invalid JSON in canvas_dimensions message: {e}")
            
            # Add a handler for refresh_from_db message
            elif message == "refresh_from_db":
                if self.refresh_timeline_from_db:
                    logger.info("Received refresh_from_db command")
                    # Refresh timeline data from database
                    self.refresh_timeline_from_db()
                    
                    # Log clip info after database refresh
                    # Get access to the timeline manager from main.py
                    from main import get_timeline_manager
                    try:
                        timeline_manager = get_timeline_manager()
                        if timeline_manager:
                            timeline_state = timeline_manager.get_timeline_state()
                            if timeline_state and "videos" in timeline_state:
                                clips = timeline_state["videos"]
                                logger.info(f"WS refresh_from_db: Processing {len(clips)} clips after database refresh")
                                for i, video in enumerate(clips):
                                    start_ms = video.get('startTimeOnTrackMs')
                                    end_ms = video.get('endTimeOnTrackMs')
                                    src_start = video.get('startTimeInSourceMs')
                                    src_end = video.get('endTimeInSourceMs')
                                    logger.info(f"WS refresh_from_db: Clip[{i}] track time: {start_ms}-{end_ms}ms, source time: {src_start}-{src_end}ms")
                    except ImportError:
                        logger.warning("Could not import get_timeline_manager - debug info limited")
                    except Exception as e:
                        logger.warning(f"Error accessing timeline data for debug: {e}")
                    
                    # Force a frame refresh by seeking to the current frame
                    current_frame = self.seek(self.seek(0))  # Get current frame index
                    frame_bytes = self.get_frame(current_frame)
                    if frame_bytes and websocket:
                        # Send the refreshed frame
                        encoded_frame = base64.b64encode(frame_bytes).decode('utf-8')
                        await websocket.send(encoded_frame)
                        logger.info(f"Refreshed frame after database update")
                    
                    # Send pause state update to ensure UI is in sync
                    await self.send_state_update(websocket, False)
                else:
                    logger.warning("Received refresh_from_db command but callback is not set")
                    
            elif message.startswith('{"type":"clips"'): # Check for the new JSON format
                try:
                    data = json.loads(message)
                    if data.get('type') == 'clips':
                        video_data = data.get('data', [])
                        logger.info(f"Received 'clips' message with {len(video_data)} clips.")
                        # Log the received raw data (truncated)
                        truncated_data = str(video_data)[:500]
                        logger.debug(f"Raw clips data received (truncated): {truncated_data}")
                        
                        # Instead of directly updating, trigger database refresh
                        logger.info("Legacy clips message received - refreshing from database instead")
                        if self.refresh_timeline_from_db:
                            self.refresh_timeline_from_db()
                        else:
                            # Fallback to direct update if callback not available
                            self.update_timeline(video_data)
                    else:
                        logger.warning(f"Received JSON message with unknown type: {data.get('type')}")
                except json.JSONDecodeError as e:
                    logger.error(f"Invalid JSON received: {message[:200]}... Error: {e}")
                except Exception as e:
                    logger.error(f"Error processing 'clips' message: {e}")
                    
            # Handle sync_clips message type (similar to clips)
            elif message.startswith('{"type":"sync_clips"'):
                try:
                    data = json.loads(message)
                    if data.get('type') == 'sync_clips':
                        logger.info("Received 'sync_clips' message - refreshing from database")
                        
                        # Use new database refresh approach instead of message data
                        if self.refresh_timeline_from_db:
                            self.refresh_timeline_from_db()
                        else:
                            # Fallback to legacy message approach if callback not set
                            video_data = data.get('payload', [])
                            truncated_data = str(video_data)[:500]
                            logger.debug(f"Raw sync_clips data received (truncated): {truncated_data}")
                            self.update_timeline(video_data)
                    else:
                        logger.warning(f"Received unexpected message format: {data.get('type')}")
                except json.JSONDecodeError as e:
                    logger.error(f"Invalid JSON in sync_clips message: {e}")
                except Exception as e:
                    logger.error(f"Error processing 'sync_clips' message: {e}")

            # Handle JSON-formatted seek messages
            elif message.startswith('{"type":"seek"'):
                try:
                    data = json.loads(message)
                    if data.get('type') == 'seek':
                        payload = data.get('payload', {})
                        frame = payload.get('frame')
                        
                        if frame is not None:
                            logger.info(f"Received JSON seek message for frame {frame}")
                            
                            # Seek to the requested frame
                            actual_frame = self.seek(frame)
                            
                            # Always stop playback during manual seeking to prevent auto-play
                            await self.stop_playback()
                            
                            # Send the current frame immediately
                            frame_bytes = self.get_frame(actual_frame)
                            if frame_bytes and websocket:
                                # Send the refreshed frame
                                encoded_frame = base64.b64encode(frame_bytes).decode('utf-8')
                                await websocket.send(encoded_frame)
                                
                            # Confirm to client that we're in paused state after seeking
                            await self.send_state_update(websocket, False)
                        else:
                            logger.warning(f"Invalid 'frame' value in seek message: {payload}")
                    else:
                        logger.warning(f"Received JSON message with unexpected type: {data.get('type')}")
                except json.JSONDecodeError as e:
                    logger.error(f"Invalid JSON in seek message: {e}")
                except Exception as e:
                    logger.error(f"Error processing 'seek' message: {e}")

            # Handle playback control messages
            elif message.startswith('{"type":"playback"'):
                try:
                    data = json.loads(message)
                    if data.get('type') == 'playback':
                        payload = data.get('payload', {})
                        is_playing = payload.get('playing')
                        if is_playing is True:
                            logger.info("Received 'playback' message: playing=True")
                            await self.start_playback()
                            await self.send_state_update(websocket, True)
                        elif is_playing is False:
                            logger.info("Received 'playback' message: playing=False")
                            await self.stop_playback()
                            await self.send_state_update(websocket, False)
                        else:
                            logger.warning(f"Invalid 'playing' value in playback message: {payload}")
                    else:
                        logger.warning(f"Received JSON message with unexpected type: {data.get('type')}")
                except json.JSONDecodeError as e:
                    logger.error(f"Invalid JSON in playback message: {e}")
                except Exception as e:
                    logger.error(f"Error processing 'playback' message: {e}")
                    
            # Handle direct clip position update messages
            elif message.startswith('{"type":"clip_position_update"'):
                try:
                    data = json.loads(message)
                    if data.get('type') == 'clip_position_update':
                        payload = data.get('payload', {})
                        clip_id = payload.get('clip_id')
                        position = payload.get('position', {})
                        
                        if clip_id is not None and position:
                            logger.info(f"Received clip position update for clip ID {clip_id}: {position}")
                            
                            # Get access to the timeline manager from main.py
                            from main import get_timeline_manager
                            try:
                                timeline_manager = get_timeline_manager()
                                if timeline_manager:
                                    # Find the clip by ID in current_videos
                                    for clip in timeline_manager.current_videos:
                                        if clip.get('id') == clip_id:
                                            # Update the previewRect in the clip's metadata
                                            if 'metadata' not in clip:
                                                clip['metadata'] = {}
                                            if 'previewRect' not in clip['metadata']:
                                                clip['metadata']['previewRect'] = {}
                                                
                                            # Update the position values
                                            clip['metadata']['previewRect'] = {
                                                'left': position.get('left', 0),
                                                'top': position.get('top', 0),
                                                'width': position.get('width', 1280),
                                                'height': position.get('height', 720)
                                            }
                                            logger.info(f"Updated clip {clip_id} position: {clip['metadata']['previewRect']}")
                                            
                                            # Force frame cache clear and refresh
                                            from frame_generator import get_frame_generator
                                            frame_gen = get_frame_generator()
                                            if frame_gen:
                                                frame_gen.clear_cache()
                                                logger.info("Cleared frame cache after position update")
                                            
                                            # Force a frame refresh
                                            current_frame = self.seek(self.seek(0))  # Get current frame index
                                            frame_bytes = self.get_frame(current_frame)
                                            if frame_bytes and websocket:
                                                # Send the refreshed frame
                                                encoded_frame = base64.b64encode(frame_bytes).decode('utf-8')
                                                await websocket.send(encoded_frame)
                                                logger.info(f"Refreshed frame after position update")
                                            break
                                    else:
                                        logger.warning(f"Clip with ID {clip_id} not found in timeline")
                                else:
                                    logger.warning("Timeline manager not available")
                            except ImportError:
                                logger.warning("Could not import timeline manager - position update limited")
                            except Exception as e:
                                logger.error(f"Error updating clip position: {e}")
                        else:
                            logger.warning(f"Invalid clip_id or position in message: {payload}")
                    else:
                        logger.warning(f"Received JSON message with unexpected type: {data.get('type')}")
                except json.JSONDecodeError as e:
                    logger.error(f"Invalid JSON in clip_position_update message: {e}")
                except Exception as e:
                    logger.error(f"Error processing 'clip_position_update' message: {e}")
                    
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