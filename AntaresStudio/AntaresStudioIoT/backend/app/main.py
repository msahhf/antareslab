"""
AntaresStudio IoT Backend v2.1 — Ana Uygulama

FastAPI sunucusu (asenkron, production-ready):

  Photos API:
    POST /api/v1/photos/upload           → Fotoğraf yükleme
    POST /api/v1/photos/clean/{sid}      → rembg ile arka plan temizleme (background)
    GET  /api/v1/photos/status/{sid}     → Oturum durumu
    GET  /api/v1/photos/cleaned/{s}/{f}  → Temizlenmiş fotoğraf indir

  Pipeline API:
    POST   /api/v1/pipeline/start/{sid}    → Meshroom pipeline başlat (background)
    GET    /api/v1/pipeline/status/{pid}   → Pipeline durumu (Flutter polling)
    GET    /api/v1/pipeline/list           → Tüm pipeline'lar
    DELETE /api/v1/pipeline/cancel/{pid}   → Pipeline iptal
    GET    /api/v1/pipeline/model/{pid}    → 3D model indir (glb/obj)
    POST   /api/v1/pipeline/cleanup/{sid}  → Session temizle
    POST   /api/v1/pipeline/cleanup/cache/all → Tüm cache temizle
    GET    /api/v1/pipeline/disk-usage     → Disk kullanımı

v2.1 Değişiklikler:
  [1] Proper lifespan: model preload + graceful shutdown
  [2] Structured logging
  [3] rembg stats endpoint
"""

import logging
import time
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, HTMLResponse

from app.config import settings
from app.routers import photos, pipeline, blackbox

# ESP32 Auto-Discovery (v3.1)
from app.esp32_discovery import run_discovery_and_registration, get_registered_ip

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
# Global State (Telemetry & Logs)
# ================================================================

# Latest telemetry data from ESP32/Arduino
current_telemetry = {
    "temperature": 22.5,
    "humidity": 45,
    "soil_moisture": 512,
    "mode": "STANDBY",
    "heater_power": 0,
    "fan_sly": False,
    "fan_dz": False,
    "motor_position": 0,
    "is_homed": False,
    "timestamp": time.time(),
}

# System logs buffer for dashboard
system_logs = []

def add_system_log(message: str, level: str = "INFO"):
    """Add a log entry for the dashboard terminal."""
    system_logs.append({
        "timestamp": time.time(),
        "message": message,
        "level": level,
    })
    # Keep only last 500 entries
    if len(system_logs) > 500:
        system_logs.pop(0)
    logger.info(f"[DASHBOARD] {message}")


# ================================================================
# Lifespan (Startup + Shutdown)
# ================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifecycle with ESP32 auto-discovery."""
    logger.info("╔══════════════════════════════════════╗")
    logger.info("║  AntaresStudio IoT - Backend v3.1.0  ║")
    logger.info("║  Auto-Discovery Ready                ║")
    logger.info("╚══════════════════════════════════════╝")
    logger.info(f"Upload Dir   : {settings.UPLOAD_DIR}")
    logger.info(f"Cleaned Dir  : {settings.CLEANED_DIR}")
    logger.info(f"Output Dir   : {settings.OUTPUT_DIR}")
    logger.info(f"Models Dir   : {settings.MODELS_DIR}")
    logger.info(f"rembg Model  : {settings.REMBG_MODEL} (LAZY)")
    logger.info(f"Meshroom     : {settings.MESHROOM_BIN_PATH}")
    logger.info(f"Target Faces : {settings.MODEL_TARGET_FACES:,}")
    logger.info(f"Output Format: {settings.MODEL_OUTPUT_FORMAT}")
    logger.info(f"Auto Cleanup : {settings.AUTO_CLEANUP_CACHE}")
    
    # [v3.1] ESP32 Auto-Discovery & Registration
    # This finds the PC's IP on ESP32 subnet and registers with ESP32
    registered_ip = await run_discovery_and_registration(port=settings.PORT)
    if registered_ip:
        logger.info(f"[ESP32] Auto-registration complete. Backend IP: {registered_ip}")
    else:
        logger.warning("[ESP32] Auto-registration failed. ESP32 will use default fallback.")
        logger.warning("        Make sure PC is connected to Wi-Fi: ANTARES_KAPSUL_LAB")
    
    yield
    
    # [1] Graceful shutdown
    logger.info("Backend kapatılıyor...")
    photos.rembg_service.shutdown()
    pipeline.meshroom_service.shutdown()
    logger.info("Tüm servisler kapatıldı.")


# ================================================================
# FastAPI Uygulaması
# ================================================================

app = FastAPI(
    title="AntaresStudio IoT Backend",
    description=(
        "Fotogrametri pipeline: Fotoğraf → rembg → Meshroom → Decimation → 3D Model (.glb)\n\n"
        "## Özellikler\n"
        "- **Asenkron pipeline**: Ağır işlemler arka planda çalışır, API bloklanmaz\n"
        "- **rembg batch**: Model bir kez yüklenir, tüm fotoğraflarda paylaşılır\n"
        "- **Model optimizasyonu**: Yüksek poligonlu OBJ → düşük poligonlu GLB\n"
        "- **Otomatik cleanup**: Pipeline bitince GB'larca cache silinir\n"
    ),
    version="2.1.0",
    lifespan=lifespan,
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Static files (for dashboard)
static_dir = Path(__file__).parent / "static"
static_dir.mkdir(exist_ok=True)
app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

# Router'ları ekle
app.include_router(photos.router, prefix="/api/v1/photos", tags=["Photos"])
app.include_router(pipeline.router, prefix="/api/v1/pipeline", tags=["Pipeline"])
app.include_router(blackbox.router, prefix="/api/v1/blackbox", tags=["Black Box"])


# ================================================================
# Dashboard & Root
# ================================================================

@app.get("/", response_class=HTMLResponse)
async def root_dashboard():
    """Serve the web dashboard."""
    dashboard_file = static_dir / "index.html"
    if dashboard_file.exists():
        return FileResponse(str(dashboard_file))
    return HTMLResponse("""
    <!DOCTYPE html>
    <html>
    <head><title>Antares Backend</title></head>
    <body style="font-family: sans-serif; padding: 40px; background: #0a0e17; color: #fff;">
        <h1>🛰️ Antares Archaeology Capsule Backend</h1>
        <p>Dashboard file not found. Please ensure <code>static/index.html</code> exists.</p>
        <p>API Documentation: <a href="/docs" style="color: #00f0ff;">/docs</a></p>
    </body>
    </html>
    """)


@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard_redirect():
    """Redirect to root dashboard."""
    return await root_dashboard()


# ================================================================
# Telemetry API (ESP32 → Backend → Dashboard)
# ================================================================

@app.get("/api/telemetry")
async def get_telemetry():
    """
    Get latest telemetry data from the archaeology capsule.
    Called by the web dashboard every 2 seconds.
    """
    return {
        **current_telemetry,
        "age_seconds": time.time() - current_telemetry["timestamp"],
    }


@app.post("/api/telemetry")
async def post_telemetry(request: Request):
    """
    Receive telemetry data from ESP32 or Flutter app.
    Payload: {"temperature": 22.5, "humidity": 45, "soil_moisture": 512, "mode": "AUTO"}
    """
    global current_telemetry
    try:
        data = await request.json()
        current_telemetry.update(data)
        current_telemetry["timestamp"] = time.time()
        
        # Log significant changes
        if data.get("mode") and data.get("mode") != current_telemetry.get("mode"):
            add_system_log(f"Mode changed to: {data['mode']}", "INFO")
        
        return {"status": "ok", "received": True}
    except Exception as e:
        logger.error(f"Telemetry parse error: {e}")
        return {"status": "error", "message": str(e)}


# ================================================================
# Logs API (for dashboard terminal)
# ================================================================

@app.get("/api/logs")
async def get_logs(limit: int = 50):
    """Get recent system logs for the dashboard terminal."""
    return {
        "logs": system_logs[-limit:],
        "total": len(system_logs),
    }


# ================================================================
# API Info (JSON endpoint for programmatic access)
# ================================================================

@app.get("/api/info")
async def api_info():
    """API information in JSON format."""
    return {
        "service": "AntaresStudio IoT Backend",
        "version": "2.2.0",
        "endpoints": {
            "photos_upload": "/api/v1/photos/upload",
            "photos_clean": "/api/v1/photos/clean/{session_id}",
            "photos_status": "/api/v1/photos/status/{session_id}",
            "pipeline_start": "/api/v1/pipeline/start/{session_id}",
            "pipeline_status": "/api/v1/pipeline/status/{pipeline_id}",
            "pipeline_model": "/api/v1/pipeline/model/{pipeline_id}",
            "pipeline_cleanup": "/api/v1/pipeline/cleanup/{session_id}",
            "pipeline_disk": "/api/v1/pipeline/disk-usage",
            "telemetry": "/api/telemetry",
            "logs": "/api/logs",
            "docs": "/docs",
            "dashboard": "/",
        },
    }


@app.get("/health")
async def health():
    """
    Health check with ESP32 registration status.
    
    Flutter BackendService.isHealthy() uses this endpoint.
    """
    meshroom_ok = pipeline.meshroom_service.is_available()
    rembg_stats = photos.rembg_service.stats
    registered_ip = get_registered_ip()
    
    return {
        "status": "healthy",
        "version": "3.1.0",
        "meshroom_available": meshroom_ok,
        "rembg": {
            "model_loaded": rembg_stats["model_loaded"],
            "model_name": rembg_stats["model_name"],
            "total_processed": rembg_stats["total_processed"],
            "avg_time_sec": round(rembg_stats["avg_time_sec"], 2),
        },
        "active_pipelines": len([
            p for p in pipeline.pipelines.values() if p["status"] == "running"
        ]),
        "esp32": {
            "registered_ip": registered_ip,
            "esp32_ap": "192.168.4.1",
            "auto_discovery": "enabled",
        },
        "telemetry": {
            "last_update": current_telemetry["timestamp"],
            "capsule_mode": current_telemetry["mode"],
        },
    }


@app.get("/api/esp32/status")
async def esp32_registration_status():
    """Get ESP32 registration and network status."""
    from app.esp32_discovery import get_network_interfaces, is_same_subnet
    
    registered_ip = get_registered_ip()
    interfaces = get_network_interfaces()
    
    # Find interface on ESP32 subnet
    esp32_interface = None
    for iface in interfaces:
        if iface.ip_address.startswith("192.168.4."):
            esp32_interface = iface
            break
    
    return {
        "registered_ip": registered_ip,
        "esp32_ap_ip": "192.168.4.1",
        "is_on_esp32_subnet": esp32_interface is not None,
        "network_interface": esp32_interface.__dict__ if esp32_interface else None,
        "all_interfaces": [i.__dict__ for i in interfaces],
        "instructions": "Connect PC to Wi-Fi: ANTARES_KAPSUL_LAB for auto-discovery",
    }
