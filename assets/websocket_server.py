#!/usr/bin/env python3
import asyncio
import websockets
import logging
import json
from typing import Set, Any, Callable

logger = logging.getLogger('video_stream_server')

class WebSocketServer:
    def __init__(self, port: int, host: str, message_handler_callback: Callable):
        """
        Initialize the WebSocket server
        
        Args:
            port: The port number to run the server on
            host: The host address to bind to
            message_handler_callback: Function to handle incoming messages
        """
        self.port = port
        self.host = host
        self.clients: Set[Any] = set()
        self.handle_message = message_handler_callback
        self.server = None
        self.shutdown_event = asyncio.Event()

    async def register(self, websocket):
        """Register a new client connection"""
        self.clients.add(websocket)
        logger.info(f"Client connected. Total clients: {len(self.clients)}")

    async def unregister(self, websocket):
        """Unregister a client connection"""
        self.clients.remove(websocket)
        logger.info(f"Client disconnected. Total clients: {len(self.clients)}")

    async def send_frame_to_all(self, frame_data: str):
        """Send a frame to all connected clients."""
        if not self.clients:
            return
            
        disconnected_clients = set()
        # Use asyncio.gather for potential performance improvement
        tasks = []
        for client in self.clients:
            tasks.append(self._send_to_client(client, frame_data))
        
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Check for disconnected clients based on exceptions
        for client, result in zip(list(self.clients), results):
            if isinstance(result, websockets.exceptions.ConnectionClosed):
                disconnected_clients.add(client)
                
        # Remove disconnected clients
        for client in disconnected_clients:
            await self.unregister(client)

    async def _send_to_client(self, client, message: str):
        """Helper to send a message to a single client and handle potential closure"""
        try:
            await client.send(message)
        except websockets.exceptions.ConnectionClosed:
            logger.debug("Attempted to send to a closed connection.")
            raise # Re-raise to be caught by gather

    async def send_state_update(self, websocket, is_playing: bool, current_frame: int):
        """Send a state update message to a specific client."""
        try:
            # Ensure compact JSON with no space after colon to match what Flutter expects
            state_message = json.dumps({
                "type": "state", 
                "playing": is_playing,
                "frame": current_frame
            }, separators=(',', ':'))
            await websocket.send(state_message)
            logger.debug(f"Sent state update to {websocket.remote_address}: {state_message[:50]}...")
        except Exception as e:
            logger.error(f"Error sending state update: {e}")

    async def handler(self, websocket, path=''):
        """Handle WebSocket connections."""
        await self.register(websocket)
        try:
            async for message in websocket:
                await self.handle_message(websocket, message)
        except websockets.exceptions.ConnectionClosed:
            logger.info(f"Connection closed by {websocket.remote_address}")
        except Exception as e:
             logger.error(f"Error in handler for {websocket.remote_address}: {e}")
        finally:
            await self.unregister(websocket)

    async def run(self):
        """Run the WebSocket server."""
        # Create the server with the handler
        self.server = await websockets.serve(self.handler, self.host, self.port)
        logger.info(f"WebSocket server started on ws://{self.host}:{self.port}")
        
        # Wait for the shutdown event
        await self.shutdown_event.wait()
        
        # Close the server when shutting down
        self.server.close()
        await self.server.wait_closed()
        logger.info("WebSocket server shut down")

    def shutdown(self):
        """Shutdown the server."""
        logger.info("Shutting down WebSocket server...")
        self.shutdown_event.set()