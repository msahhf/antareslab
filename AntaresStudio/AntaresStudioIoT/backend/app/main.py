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
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
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
    """Uygulama yaşam döngüsü."""
    logger.info("╔══════════════════════════════════════╗")
    logger.info("║  AntaresStudio IoT - Backend v2.1.0  ║")
    logger.info("╚══════════════════════════════════════╝")
    logger.info(f"Upload Dir   : {settings.UPLOAD_DIR}")
    logger.info(f"Cleaned Dir  : {settings.CLEANED_DIR}")
    logger.info(f"Output Dir   : {settings.OUTPUT_DIR}")
    logger.info(f"Models Dir   : {settings.MODELS_DIR}")
    logger.info(f"rembg Model  : {settings.REMBG_MODEL}")
    logger.info(f"Meshroom     : {settings.MESHROOM_BIN_PATH}")
    logger.info(f"Target Faces : {settings.MODEL_TARGET_FACES:,}")
    logger.info(f"Output Format: {settings.MODEL_OUTPUT_FORMAT}")
    logger.info(f"Auto Cleanup : {settings.AUTO_CLEANUP_CACHE}")
    
    # [1] rembg modelini önceden yükle (ilk istek gecikmesini önler)
    logger.info("rembg modeli önceden yükleniyor...")
    photos.rembg_service._ensure_session()
    
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

# Router'ları ekle
app.include_router(photos.router, prefix="/api/v1/photos", tags=["Photos"])
app.include_router(pipeline.router, prefix="/api/v1/pipeline", tags=["Pipeline"])


# ================================================================
# Root & Health
# ================================================================

@app.get("/")
async def root():
    return {
        "service": "AntaresStudio IoT Backend",
        "version": "2.1.0",
        "endpoints": {
            "photos_upload": "/api/v1/photos/upload",
            "photos_clean": "/api/v1/photos/clean/{session_id}",
            "photos_status": "/api/v1/photos/status/{session_id}",
            "pipeline_start": "/api/v1/pipeline/start/{session_id}",
            "pipeline_status": "/api/v1/pipeline/status/{pipeline_id}",
            "pipeline_model": "/api/v1/pipeline/model/{pipeline_id}",
            "pipeline_cleanup": "/api/v1/pipeline/cleanup/{session_id}",
            "pipeline_disk": "/api/v1/pipeline/disk-usage",
            "docs": "/docs",
        },
    }


@app.get("/health")
async def health():
    """
    Sağlık kontrolü.
    
    Flutter BackendService.isHealthy() bu endpoint'i kontrol eder.
    """
    meshroom_ok = pipeline.meshroom_service.is_available()
    rembg_stats = photos.rembg_service.stats
    
    return {
        "status": "healthy",
        "version": "2.1.0",
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
    }
