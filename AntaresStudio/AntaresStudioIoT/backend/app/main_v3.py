"""
AntaresStudio IoT Backend v3.0 — Production Architecture

Production-ready backend with:
  [SQLite] Persistent telemetry, sessions, and pipelines
  [WebSocket] Real-time telemetry and pipeline progress (replaces polling)
  [Lazy Loading] rembg model loads on-demand, auto-unloads after inactivity
  [Direct Upload] ESP32-CAM HTTP POST bypasses Arduino UART

API Endpoints:

  Photos API:
    POST /api/v1/photos/upload              → Flutter form-based upload
    POST /api/v1/photos/esp32-direct        → ESP32-CAM binary upload (optimized)
    POST /api/v1/photos/esp32-telemetry     → ESP32 sensor data ingestion
    POST /api/v1/photos/clean/{sid}         → rembg batch processing
    GET  /api/v1/photos/status/{sid}        → Session status from SQLite
    GET  /api/v1/photos/cleaned/{s}/{f}     → Download processed image
    GET  /api/v1/photos/list              → List all sessions

  Pipeline API:
    POST   /api/v1/pipeline/start/{sid}     → Start Meshroom pipeline
    GET    /api/v1/pipeline/status/{pid}    → Legacy polling endpoint
    GET    /api/v1/pipeline/list            → All pipelines from DB
    DELETE /api/v1/pipeline/cancel/{pid}    → Cancel pipeline
    GET    /api/v1/pipeline/model/{pid}       → Download 3D model
    POST   /api/v1/pipeline/cleanup/{sid}   → Clean session
    POST   /api/v1/pipeline/cleanup/cache/all → Auto-cleanup all cache
    GET    /api/v1/pipeline/disk-usage      → Storage stats

  WebSocket Real-Time:
    WS   /ws/telemetry                      → Live telemetry stream
    WS   /ws/pipeline/{pid}                 → Pipeline progress stream
    WS   /ws/logs                         → System logs stream

  Telemetry (REST fallback):
    POST /api/telemetry                     → Receive telemetry (ESP32/Flutter)
    GET  /api/telemetry                     → Latest telemetry from DB
    GET  /api/telemetry/history             → Historical data (24h)

  System:
    GET  /                                  → Web Dashboard
    GET  /health                            → Health check
    GET  /api/info                          → API documentation

v3.0 Changes:
  [1] SQLite database with SQLAlchemy ORM
  [2] WebSocket real-time communication (replaces polling)
  [3] Lazy rembg loading (1.1GB RAM freed at idle)
  [4] ESP32-CAM direct HTTP upload (bypass Arduino)
  [5] Persistent session and pipeline tracking
"""

import logging
import time
from contextlib import asynccontextmanager
from pathlib import Path
from datetime import datetime

from fastapi import FastAPI, Request, WebSocket
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, HTMLResponse

from app.config import settings
from app.database import init_database, get_db, telemetry_repo, log_repo
from app.websocket_manager import (
    ws_manager,
    handle_telemetry_websocket,
    handle_pipeline_websocket,
    handle_logs_websocket,
)
from app.routers import photos, pipeline

# ================================================================
# Logging
# ================================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("antares.main")


# ================================================================
# Lifespan (Startup + Shutdown)
# ================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifecycle - v3.0 with SQLite and WebSockets."""
    logger.info("╔══════════════════════════════════════╗")
    logger.info("║  AntaresStudio IoT - Backend v3.0.0   ║")
    logger.info("║  Production Architecture Ready       ║")
    logger.info("╚══════════════════════════════════════╝")
    
    # [1] Initialize SQLite database
    logger.info("[DB] Initializing SQLite database...")
    init_database()
    
    logger.info(f"[DB] Path: {settings.BASE_DIR / 'data' / 'antares.db'}")
    logger.info(f"[Config] Upload Dir   : {settings.UPLOAD_DIR}")
    logger.info(f"[Config] Cleaned Dir  : {settings.CLEANED_DIR}")
    logger.info(f"[Config] Output Dir   : {settings.OUTPUT_DIR}")
    logger.info(f"[Config] Models Dir   : {settings.MODELS_DIR}")
    logger.info(f"[Config] rembg Model  : {settings.REMBG_MODEL} (LAZY LOADED)")
    logger.info(f"[Config] Meshroom     : {settings.MESHROOM_BIN_PATH}")
    logger.info(f"[Config] Target Faces : {settings.MODEL_TARGET_FACES:,}")
    logger.info(f"[Config] Output Format: {settings.MODEL_OUTPUT_FORMAT}")
    
    # [2] Note: rembg is NOT preloaded - lazy loading saves 1.1GB RAM
    logger.info("[Rembg] Model will load on first /clean request (lazy)")
    
    # [3] WebSocket manager is ready
    logger.info("[WebSocket] Real-time endpoints ready")
    
    # Log startup
    try:
        db = get_db()
        log_repo.add_log(db, "Backend v3.0 started - SQLite + WebSockets active", "INFO", "system")
    except Exception as e:
        logger.warning(f"Could not log startup: {e}")
    
    yield
    
    # [1] Graceful shutdown
    logger.info("[Shutdown] Cleaning up...")
    
    # Shutdown services
    from app.services.rembg_service import rembg_service
    rembg_service.shutdown()
    pipeline.meshroom_service.shutdown()
    
    # Log shutdown
    try:
        db = get_db()
        log_repo.add_log(db, "Backend shutting down", "INFO", "system")
    except:
        pass
    
    logger.info("[Shutdown] All services stopped. Database closed.")


# ================================================================
# FastAPI Application
# ================================================================

app = FastAPI(
    title="AntaresStudio IoT Backend v3.0",
    description="Production-ready archaeology capsule backend with SQLite persistence and WebSocket real-time updates.",
    version="3.0.0",
    lifespan=lifespan,
)

# CORS for Flutter web
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Static files (dashboard)
static_dir = Path(__file__).parent / "static"
static_dir.mkdir(exist_ok=True)
app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

# API Routers
app.include_router(photos.router, prefix="/api/v1/photos", tags=["Photos"])
app.include_router(pipeline.router, prefix="/api/v1/pipeline", tags=["Pipeline"])


# ================================================================
# WebSocket Endpoints (Real-Time)
# ================================================================

@app.websocket("/ws/telemetry")
async def websocket_telemetry(websocket: WebSocket):
    """
    WebSocket endpoint for real-time telemetry streaming.
    
    Clients subscribe here to receive live sensor updates
    instead of polling /api/telemetry.
    """
    await handle_telemetry_websocket(websocket)


@app.websocket("/ws/pipeline/{pipeline_id}")
async def websocket_pipeline(websocket: WebSocket, pipeline_id: str):
    """
    WebSocket endpoint for specific pipeline progress updates.
    
    Replaces polling /api/v1/pipeline/status/{pid} with
    push-based real-time progress notifications.
    """
    await handle_pipeline_websocket(websocket, pipeline_id)


@app.websocket("/ws/logs")
async def websocket_logs(websocket: WebSocket):
    """
    WebSocket endpoint for system logs stream.
    
    Dashboard subscribes here for real-time terminal output.
    """
    await handle_logs_websocket(websocket)


# ================================================================
# Dashboard & Root
# ================================================================

@app.get("/", response_class=HTMLResponse)
async def root_dashboard():
    """Serve web dashboard."""
    dashboard_file = static_dir / "index.html"
    if dashboard_file.exists():
        return FileResponse(str(dashboard_file))
    return HTMLResponse("""
    <!DOCTYPE html>
    <html>
    <head><title>Antares Backend v3.0</title></head>
    <body style="font-family: sans-serif; padding: 40px; background: #0a0e17; color: #fff;">
        <h1>🛰️ Antares Archaeology Capsule Backend v3.0</h1>
        <p>Dashboard file not found. Please ensure <code>static/index.html</code> exists.</p>
        <p>WebSockets: /ws/telemetry, /ws/pipeline/{id}, /ws/logs</p>
        <p>API Docs: <a href="/docs" style="color: #00f0ff;">/docs</a></p>
    </body>
    </html>
    """)


@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard_redirect():
    """Redirect to root dashboard."""
    return await root_dashboard()


# ================================================================
# Telemetry API (REST + Database)
# ================================================================

@app.get("/api/telemetry")
async def get_telemetry():
    """
    Get latest telemetry from SQLite database.
    Called by dashboard/Flutter when not using WebSocket.
    """
    db = get_db()
    reading = telemetry_repo.get_latest(db)
    
    if reading:
        return reading.to_dict()
    
    # Fallback if no data yet
    return {
        "temperature": 22.5,
        "humidity": 45,
        "soil_moisture": 512,
        "mode": "STANDBY",
        "timestamp": datetime.utcnow().isoformat(),
        "source": "default",
    }


@app.get("/api/telemetry/history")
async def get_telemetry_history(hours: int = 24, limit: int = 1000):
    """Get historical telemetry data for charts/trends."""
    db = get_db()
    readings = telemetry_repo.get_history(db, hours=hours, limit=limit)
    return {
        "readings": [r.to_dict() for r in readings],
        "count": len(readings),
        "hours": hours,
    }


@app.post("/api/telemetry")
async def post_telemetry(request: Request):
    """
    Receive telemetry data from ESP32 or Flutter app.
    
    Payload formats:
      JSON: {"temperature": 25.5, "humidity": 60, "soil_moisture": 512, "mode": "AUTO"}
      CSV: "DATA,25.5,60,750,AUTO,0,false,false,0,false"
    
    Data is saved to SQLite and broadcast via WebSocket.
    """
    db = get_db()
    
    try:
        body = await request.body()
        content_type = request.headers.get("content-type", "")
        
        data = {}
        
        # Parse JSON
        if "json" in content_type or body[:1] == b'{':
            import json
            json_data = json.loads(body)
            data = {
                "temperature": json_data.get("temperature"),
                "humidity": json_data.get("humidity"),
                "soil_moisture": json_data.get("soil_moisture"),
                "mode": json_data.get("mode", "STANDBY"),
                "heater_power": json_data.get("heater_power", 0),
                "fan_sly": json_data.get("fan_sly", False),
                "fan_dz": json_data.get("fan_dz", False),
                "motor_position": json_data.get("motor_position", 0),
                "is_homed": json_data.get("is_homed", False),
                "source": json_data.get("source", "http"),
            }
        else:
            # Parse CSV: DATA,25.5,60,750,AUTO,0,false,false,0,false
            text = body.decode('utf-8', errors='ignore').strip()
            if text.startswith("DATA,"):
                parts = text.split(',')
                if len(parts) >= 5:
                    data = {
                        "temperature": float(parts[1]) if parts[1] else None,
                        "humidity": int(parts[2]) if parts[2].isdigit() else None,
                        "soil_moisture": int(parts[3]) if parts[3].isdigit() else None,
                        "mode": parts[4] if len(parts) > 4 else "STANDBY",
                        "source": "esp32-csv",
                    }
        
        if data:
            # Save to database
            reading = telemetry_repo.save_telemetry(db, **data)
            
            # Broadcast via WebSocket
            await ws_manager.broadcast_telemetry(reading.to_dict())
            
            return {"status": "ok", "received": True, "id": reading.id}
        
        return {"status": "error", "message": "Could not parse telemetry"}
        
    except Exception as e:
        logger.error(f"Telemetry parse error: {e}")
        return {"status": "error", "message": str(e)}


# ================================================================
# System Logs API
# ================================================================

@app.get("/api/logs")
async def get_logs(limit: int = 100):
    """Get recent system logs from database."""
    db = get_db()
    logs = log_repo.get_recent(db, limit)
    return {
        "logs": [log.to_dict() for log in logs],
        "total": len(logs),
    }


# ================================================================
# API Info
# ================================================================

@app.get("/api/info")
async def api_info():
    """API documentation and endpoint listing."""
    return {
        "service": "AntaresStudio IoT Backend",
        "version": "3.0.0",
        "architecture": "SQLite + WebSocket + Lazy Loading",
        "endpoints": {
            "photos_upload": "/api/v1/photos/upload",
            "photos_esp32_direct": "/api/v1/photos/esp32-direct",
            "photos_esp32_telemetry": "/api/v1/photos/esp32-telemetry",
            "photos_clean": "/api/v1/photos/clean/{session_id}",
            "photos_status": "/api/v1/photos/status/{session_id}",
            "photos_list": "/api/v1/photos/list",
            "pipeline_start": "/api/v1/pipeline/start/{session_id}",
            "pipeline_status": "/api/v1/pipeline/status/{pipeline_id}",
            "pipeline_model": "/api/v1/pipeline/model/{pipeline_id}",
            "pipeline_cleanup": "/api/v1/pipeline/cleanup/{session_id}",
            "pipeline_disk": "/api/v1/pipeline/disk-usage",
            "telemetry_rest": "/api/telemetry",
            "telemetry_history": "/api/telemetry/history",
            "logs": "/api/logs",
            "ws_telemetry": "/ws/telemetry",
            "ws_pipeline": "/ws/pipeline/{pipeline_id}",
            "ws_logs": "/ws/logs",
            "docs": "/docs",
            "dashboard": "/",
        },
    }


# ================================================================
# Health Check
# ================================================================

@app.get("/health")
async def health():
    """
    Health check with full system status.
    
    Flutter BackendService.isHealthy() and dashboard use this.
    """
    from app.services.rembg_service import rembg_service
    
    meshroom_ok = pipeline.meshroom_service.is_available()
    rembg_stats = rembg_service.stats
    
    # Get latest telemetry from DB
    db = get_db()
    latest = telemetry_repo.get_latest(db)
    
    return {
        "status": "healthy",
        "version": "3.0.0",
        "architecture": "SQLite + WebSocket + Lazy Loading",
        "meshroom_available": meshroom_ok,
        "rembg": {
            "model_loaded": rembg_stats["model_loaded"],
            "model_name": rembg_stats["model_name"],
            "total_processed": rembg_stats["total_processed"],
            "avg_time_sec": round(rembg_stats.get("avg_time_sec", 0), 2),
            "idle_seconds": round(rembg_stats.get("model_idle_seconds", 0), 1),
            "auto_unload_after": rembg_stats.get("auto_unload_seconds", 300),
        },
        "active_pipelines": len([
            p for p in pipeline.pipelines.values() if p["status"] == "running"
        ]),
        "telemetry": {
            "database": "SQLite",
            "last_update": latest.timestamp.isoformat() if latest else None,
            "capsule_mode": latest.mode if latest else "UNKNOWN",
            "history_hours": 24,
        },
        "websockets": await ws_manager.get_connection_stats(),
    }


# ================================================================
# Debug Endpoints (Development)
# ================================================================

@app.get("/api/debug/database/stats")
async def debug_database_stats():
    """Debug: Database statistics."""
    db = get_db()
    from app.database import TelemetryReading, Session, Pipeline, SystemLog
    
    return {
        "telemetry_count": db.query(TelemetryReading).count(),
        "session_count": db.query(Session).count(),
        "pipeline_count": db.query(Pipeline).count(),
        "log_count": db.query(SystemLog).count(),
    }
