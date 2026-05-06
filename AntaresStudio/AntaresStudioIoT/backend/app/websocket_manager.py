"""
AntaresStudio IoT Backend - WebSocket Manager v3.0

Real-time communication hub for telemetry and pipeline updates.
Replaces polling with push-based architecture.
"""

import asyncio
import json
import logging
from typing import Dict, List, Set
from datetime import datetime

from fastapi import WebSocket, WebSocketDisconnect
from starlette.websockets import WebSocketState

logger = logging.getLogger("antares.websocket")


class ConnectionManager:
    """Manages WebSocket connections for real-time updates."""
    
    def __init__(self):
        # Active connections by type
        self.telemetry_connections: Set[WebSocket] = set()
        self.pipeline_connections: Dict[str, Set[WebSocket]] = {}  # pipeline_id -> connections
        self.log_connections: Set[WebSocket] = set()
        
        # Track all connections for broadcasting
        self.all_connections: Set[WebSocket] = set()
        
        # Circuit breaker for connection floods
        self._connection_lock = asyncio.Lock()
    
    async def connect_telemetry(self, websocket: WebSocket):
        """Accept telemetry subscription connection."""
        await websocket.accept()
        async with self._connection_lock:
            self.telemetry_connections.add(websocket)
            self.all_connections.add(websocket)
        logger.info(f"Telemetry client connected. Total: {len(self.telemetry_connections)}")
    
    async def connect_pipeline(self, websocket: WebSocket, pipeline_id: str):
        """Accept pipeline-specific connection."""
        await websocket.accept()
        async with self._connection_lock:
            if pipeline_id not in self.pipeline_connections:
                self.pipeline_connections[pipeline_id] = set()
            self.pipeline_connections[pipeline_id].add(websocket)
            self.all_connections.add(websocket)
        logger.info(f"Pipeline {pipeline_id[:8]}... client connected")
    
    async def connect_logs(self, websocket: WebSocket):
        """Accept system log subscription."""
        await websocket.accept()
        async with self._connection_lock:
            self.log_connections.add(websocket)
            self.all_connections.add(websocket)
        logger.info(f"Log client connected. Total: {len(self.log_connections)}")
    
    async def disconnect(self, websocket: WebSocket):
        """Remove connection from all tracking sets."""
        async with self._connection_lock:
            # Remove from all sets
            self.telemetry_connections.discard(websocket)
            self.log_connections.discard(websocket)
            self.all_connections.discard(websocket)
            
            # Clean up pipeline connections
            empty_pipelines = []
            for pid, conns in self.pipeline_connections.items():
                conns.discard(websocket)
                if not conns:
                    empty_pipelines.append(pid)
            
            # Remove empty pipeline entries
            for pid in empty_pipelines:
                del self.pipeline_connections[pid]
    
    async def broadcast_telemetry(self, data: dict):
        """Broadcast telemetry update to all subscribers."""
        if not self.telemetry_connections:
            return
        
        message = json.dumps({
            "type": "telemetry",
            "timestamp": datetime.utcnow().isoformat(),
            "data": data,
        })
        
        disconnected = []
        for conn in self.telemetry_connections:
            try:
                if conn.client_state == WebSocketState.CONNECTED:
                    await conn.send_text(message)
            except Exception as e:
                logger.warning(f"Failed to send telemetry: {e}")
                disconnected.append(conn)
        
        # Clean up dead connections
        for conn in disconnected:
            await self.disconnect(conn)
    
    async def broadcast_pipeline_update(self, pipeline_id: str, data: dict):
        """Broadcast pipeline progress to specific subscribers."""
        if pipeline_id not in self.pipeline_connections:
            return
        
        message = json.dumps({
            "type": "pipeline_update",
            "pipeline_id": pipeline_id,
            "timestamp": datetime.utcnow().isoformat(),
            "data": data,
        })
        
        disconnected = []
        for conn in self.pipeline_connections[pipeline_id]:
            try:
                if conn.client_state == WebSocketState.CONNECTED:
                    await conn.send_text(message)
            except Exception as e:
                logger.warning(f"Failed to send pipeline update: {e}")
                disconnected.append(conn)
        
        for conn in disconnected:
            await self.disconnect(conn)
    
    async def broadcast_log(self, message: str, level: str = "INFO", source: str = "system"):
        """Broadcast system log to dashboard subscribers."""
        
    async def broadcast_recording_status(self, is_recording: bool, duration_seconds: int = 0, metadata: dict = None):
        """
        Broadcast Black Box recording status change to all clients.
        
        This is used by the blackbox service to notify UI when recording
        starts or stops.
        """
        if not self.telemetry_connections:
            return
        
        payload = {
            "type": "recording_status",
            "timestamp": datetime.utcnow().isoformat(),
            "is_recording": is_recording,
            "duration_seconds": duration_seconds,
        }
        
        if metadata:
            payload["metadata"] = metadata
        
        message = json.dumps(payload)
        
        disconnected = []
        for conn in self.telemetry_connections:
            try:
                if conn.client_state == WebSocketState.CONNECTED:
                    await conn.send_text(message)
            except Exception as e:
                logger.warning(f"Failed to send recording status: {e}")
                disconnected.append(conn)
        
        for conn in disconnected:
            await self.disconnect(conn)
        
        logger.debug(f"Broadcast recording status: is_recording={is_recording}")
        if not self.log_connections:
            return
        
        payload = json.dumps({
            "type": "log",
            "timestamp": datetime.utcnow().isoformat(),
            "level": level,
            "source": source,
            "message": message,
        })
        
        disconnected = []
        for conn in self.log_connections:
            try:
                if conn.client_state == WebSocketState.CONNECTED:
                    await conn.send_text(payload)
            except Exception as e:
                logger.warning(f"Failed to send log: {e}")
                disconnected.append(conn)
        
        for conn in disconnected:
            await self.disconnect(conn)
    
    async def get_connection_stats(self) -> dict:
        """Return current connection statistics."""
        return {
            "telemetry_subscribers": len(self.telemetry_connections),
            "log_subscribers": len(self.log_connections),
            "pipeline_subscriptions": len(self.pipeline_connections),
            "total_connections": len(self.all_connections),
        }


# Global WebSocket manager instance
ws_manager = ConnectionManager()


# =============================================================================
# WebSocket Helper Functions
# =============================================================================

async def handle_telemetry_websocket(websocket: WebSocket):
    """Handle telemetry WebSocket connection lifecycle."""
    await ws_manager.connect_telemetry(websocket)
    try:
        while True:
            # Keep connection alive, handle ping/pong
            data = await websocket.receive_text()
            try:
                msg = json.loads(data)
                if msg.get("action") == "ping":
                    await websocket.send_text(json.dumps({"type": "pong"}))
            except json.JSONDecodeError:
                pass
    except WebSocketDisconnect:
        await ws_manager.disconnect(websocket)
        logger.info("Telemetry client disconnected")
    except Exception as e:
        logger.error(f"Telemetry WebSocket error: {e}")
        await ws_manager.disconnect(websocket)


async def handle_pipeline_websocket(websocket: WebSocket, pipeline_id: str):
    """Handle pipeline-specific WebSocket connection."""
    await ws_manager.connect_pipeline(websocket, pipeline_id)
    try:
        # Send initial status
        await websocket.send_text(json.dumps({
            "type": "connected",
            "pipeline_id": pipeline_id,
            "message": "Subscribed to pipeline updates"
        }))
        
        while True:
            data = await websocket.receive_text()
            try:
                msg = json.loads(data)
                if msg.get("action") == "ping":
                    await websocket.send_text(json.dumps({"type": "pong"}))
            except json.JSONDecodeError:
                pass
    except WebSocketDisconnect:
        await ws_manager.disconnect(websocket)
        logger.info(f"Pipeline {pipeline_id[:8]}... client disconnected")
    except Exception as e:
        logger.error(f"Pipeline WebSocket error: {e}")
        await ws_manager.disconnect(websocket)


async def handle_logs_websocket(websocket: WebSocket):
    """Handle system logs WebSocket connection."""
    await ws_manager.connect_logs(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            try:
                msg = json.loads(data)
                if msg.get("action") == "ping":
                    await websocket.send_text(json.dumps({"type": "pong"}))
                elif msg.get("action") == "get_history":
                    # Client requests recent logs
                    limit = msg.get("limit", 50)
                    from app.database import get_db, log_repo
                    db = get_db()
                    logs = log_repo.get_recent(db, limit)
                    await websocket.send_text(json.dumps({
                        "type": "log_history",
                        "logs": [log.to_dict() for log in logs]
                    }))
            except json.JSONDecodeError:
                pass
    except WebSocketDisconnect:
        await ws_manager.disconnect(websocket)
        logger.info("Log client disconnected")
    except Exception as e:
        logger.error(f"Logs WebSocket error: {e}")
        await ws_manager.disconnect(websocket)
