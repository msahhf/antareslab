# SPDX-License-Identifier: Apache-2.0

"""
AntaresStudio IoT - Pipeline Router v2.1

Meshroom fotogrametri pipeline yönetimi.

v2.1 Değişiklikler:
  [1] Asenkron pipeline: BackgroundTasks ile çalışır, API bloklanmaz
  [3] Cleanup endpoint'leri (session & cache temizleme)
  [4] Optimize edilmiş model indirme endpoint'i
  [5] Pipeline listesi ve istatistikler
"""

import uuid
import time
import logging
from typing import Optional

from fastapi import APIRouter, HTTPException, BackgroundTasks
from fastapi.responses import FileResponse
from pathlib import Path

from app.config import settings
from app.services.meshroom_service import MeshroomService

logger = logging.getLogger("antares.pipeline")

router = APIRouter()
meshroom_service = MeshroomService()

# Pipeline durumları (bellekte — üretimde Redis/DB olabilir)
pipelines: dict = {}


@router.post("/start/{session_id}")
async def start_pipeline(
    session_id: str,
    background_tasks: BackgroundTasks,
    use_cleaned: bool = True,
):
    """
    [1] Fotogrametri pipeline'ını arka planda başlat.
    
    API hemen yanıt döner, pipeline BackgroundTask olarak çalışır.
    /status/{pipeline_id} ile asenkron takip edilir.
    
    Akış:
      1. Fotoğrafları al (temizlenmiş veya ham)
      2. Meshroom ile 3D model üret
      3. Model decimation + .glb dönüşümü (trimesh)
      4. Cache temizleme
    """
    # Kaynak dizini belirle
    if use_cleaned:
        source_dir = settings.CLEANED_DIR / session_id
    else:
        source_dir = settings.UPLOAD_DIR / session_id
    
    if not source_dir.exists():
        raise HTTPException(404, f"Kaynak dizin bulunamadı: {source_dir}")
    
    # Fotoğraf sayısını kontrol et
    photos = list(source_dir.glob("*.jpg")) + list(source_dir.glob("*.png"))
    if len(photos) < 3:
        raise HTTPException(400, f"En az 3 fotoğraf gerekli, bulunan: {len(photos)}")
    
    # Pipeline ID oluştur
    pipeline_id = str(uuid.uuid4())[:8]
    output_dir = settings.OUTPUT_DIR / session_id / pipeline_id
    output_dir.mkdir(parents=True, exist_ok=True)
    
    pipelines[pipeline_id] = {
        "session_id": session_id,
        "pipeline_id": pipeline_id,
        "status": "queued",
        "started_at": time.time(),
        "source_dir": str(source_dir),
        "output_dir": str(output_dir),
        "photo_count": len(photos),
        "progress": 0,
        "current_step": "Kuyrukta...",
        "error": None,
        "output_model": None,
        "optimized_model": None,
        "completed_at": None,
        "duration_sec": None,
        "cache_cleaned": False,
        "steps": [
            "CameraInit",
            "Feature Extraction",
            "Feature Matching",
            "Structure from Motion",
            "Depth Map Estimation",
            "Meshing",
            "Texturing",
            "Model Optimizasyonu",
            "Cache Temizleme",
        ],
    }
    
    # [1] Background task olarak başlat — API bloklanmaz
    background_tasks.add_task(
        _run_pipeline,
        pipeline_id,
        source_dir,
        output_dir,
    )
    
    logger.info(f"Pipeline başlatıldı: {pipeline_id} (session: {session_id}, {len(photos)} foto)")
    
    return {
        "success": True,
        "pipeline_id": pipeline_id,
        "session_id": session_id,
        "photo_count": len(photos),
        "message": f"Pipeline başlatıldı. /status/{pipeline_id} ile takip edin.",
    }


@router.get("/status/{pipeline_id}")
async def get_pipeline_status(pipeline_id: str):
    """
    Pipeline durumu sorgula.
    
    Flutter ScanProvider bu endpoint'i 5 saniyede bir polling eder.
    """
    if pipeline_id not in pipelines:
        raise HTTPException(404, f"Pipeline bulunamadı: {pipeline_id}")
    
    p = pipelines[pipeline_id]
    return {
        "pipeline_id": p["pipeline_id"],
        "session_id": p["session_id"],
        "status": p["status"],
        "progress": p["progress"],
        "current_step": p["current_step"],
        "error": p["error"],
        "output_model": p["output_model"],
        "optimized_model": p["optimized_model"],
        "photo_count": p["photo_count"],
        "started_at": p["started_at"],
        "completed_at": p["completed_at"],
        "duration_sec": p["duration_sec"],
        "cache_cleaned": p["cache_cleaned"],
    }


@router.get("/list")
async def list_pipelines():
    """Tüm pipeline'ları listele."""
    pipeline_list = []
    for p in pipelines.values():
        pipeline_list.append({
            "pipeline_id": p["pipeline_id"],
            "session_id": p["session_id"],
            "status": p["status"],
            "progress": p["progress"],
            "current_step": p["current_step"],
            "photo_count": p["photo_count"],
        })
    
    return {
        "pipelines": pipeline_list,
        "total": len(pipelines),
    }


@router.delete("/cancel/{pipeline_id}")
async def cancel_pipeline(pipeline_id: str):
    """Pipeline'ı iptal et."""
    if pipeline_id not in pipelines:
        raise HTTPException(404, f"Pipeline bulunamadı: {pipeline_id}")
    
    pipeline = pipelines[pipeline_id]
    if pipeline["status"] in ["completed", "error"]:
        raise HTTPException(400, "Pipeline zaten tamamlanmış veya hata vermiş.")
    
    pipeline["status"] = "cancelled"
    pipeline["current_step"] = "İptal edildi"
    meshroom_service.cancel()
    
    logger.info(f"Pipeline iptal edildi: {pipeline_id}")
    return {"success": True, "message": "Pipeline iptal edildi."}


# ================================================================
# [4] Model İndirme
# ================================================================

@router.get("/model/{pipeline_id}")
async def download_model(pipeline_id: str, optimized: bool = True):
    """
    Pipeline'ın ürettiği 3D modeli indir.
    
    Args:
        pipeline_id: Pipeline ID
        optimized: True ise optimize edilmiş (glb/gltf), False ise orijinal (obj/ply)
    """
    if pipeline_id not in pipelines:
        raise HTTPException(404, f"Pipeline bulunamadı: {pipeline_id}")
    
    pipeline = pipelines[pipeline_id]
    if pipeline["status"] != "completed":
        raise HTTPException(400, "Pipeline henüz tamamlanmadı.")
    
    # Hangi modeli döndür?
    if optimized and pipeline.get("optimized_model"):
        model_path = Path(pipeline["optimized_model"])
    elif pipeline.get("output_model"):
        model_path = Path(pipeline["output_model"])
    else:
        raise HTTPException(404, "Model dosyası bulunamadı.")
    
    if not model_path.exists():
        raise HTTPException(404, f"Model dosyası diskte bulunamadı: {model_path.name}")
    
    # MIME type
    ext = model_path.suffix.lower()
    media_types = {
        ".glb": "model/gltf-binary",
        ".gltf": "model/gltf+json",
        ".obj": "text/plain",
        ".ply": "application/octet-stream",
    }
    
    return FileResponse(
        model_path,
        media_type=media_types.get(ext, "application/octet-stream"),
        filename=model_path.name,
    )


# ================================================================
# [3] Cleanup Endpoint'leri
# ================================================================

@router.post("/cleanup/{session_id}")
async def cleanup_session(session_id: str):
    """
    Bir session'ın tüm geçici dosyalarını temizle.
    
    Pipeline bitip model Flutter'a aktarıldıktan sonra çağrılır.
    Upload, cleaned, output ve cache dizinlerini siler.
    """
    result = await meshroom_service.cleanup_session(session_id)
    
    # İlişkili pipeline'ları da güncelle
    for p in pipelines.values():
        if p["session_id"] == session_id:
            p["cache_cleaned"] = True
    
    return {"success": True, **result}


@router.post("/cleanup/cache/all")
async def cleanup_all_caches():
    """Tüm Meshroom cache'lerini temizle (GB'larca yer açar)."""
    result = await meshroom_service.cleanup_all_caches()
    return {"success": True, **result}


@router.get("/disk-usage")
async def get_disk_usage():
    """
    Tüm data dizinlerinin disk kullanımını göster.
    Flutter'da disk uyarısı göstermek için kullanılır.
    """
    def _dir_size(path: Path) -> int:
        if not path.exists():
            return 0
        return sum(f.stat().st_size for f in path.rglob("*") if f.is_file())
    
    return {
        "uploads_mb": round(_dir_size(settings.UPLOAD_DIR) / (1024**2), 1),
        "cleaned_mb": round(_dir_size(settings.CLEANED_DIR) / (1024**2), 1),
        "output_mb": round(_dir_size(settings.OUTPUT_DIR) / (1024**2), 1),
        "cache_mb": round(_dir_size(settings.MESHROOM_CACHE_DIR) / (1024**2), 1),
        "models_mb": round(_dir_size(settings.MODELS_DIR) / (1024**2), 1),
        "total_mb": round(
            sum([
                _dir_size(settings.UPLOAD_DIR),
                _dir_size(settings.CLEANED_DIR),
                _dir_size(settings.OUTPUT_DIR),
                _dir_size(settings.MESHROOM_CACHE_DIR),
                _dir_size(settings.MODELS_DIR),
            ]) / (1024**2), 1
        ),
    }


# ================================================================
# Background Task
# ================================================================

async def _run_pipeline(pipeline_id: str, source_dir, output_dir):
    """Background task: Meshroom pipeline çalıştır."""
    pipeline = pipelines[pipeline_id]
    
    try:
        pipeline["status"] = "running"
        
        # Meshroom'u çalıştır
        result = await meshroom_service.run_pipeline(
            input_dir=source_dir,
            output_dir=output_dir,
            progress_callback=lambda step, pct: _update_progress(pipeline_id, step, pct),
        )
        
        if result["success"]:
            pipeline["status"] = "completed"
            pipeline["progress"] = 100
            pipeline["current_step"] = "Tamamlandı"
            pipeline["output_model"] = result.get("model_path", "")
            pipeline["optimized_model"] = result.get("optimized_model")
            pipeline["completed_at"] = time.time()
            pipeline["duration_sec"] = round(
                pipeline["completed_at"] - pipeline["started_at"], 1
            )
            pipeline["cache_cleaned"] = settings.AUTO_CLEANUP_CACHE
            
            logger.info(
                f"Pipeline tamamlandı: {pipeline_id} "
                f"({pipeline['duration_sec']}s, {pipeline['photo_count']} foto)"
            )
        else:
            pipeline["status"] = "error"
            pipeline["error"] = result.get("error", "Bilinmeyen hata")
            logger.error(f"Pipeline hata: {pipeline_id} — {pipeline['error']}")
            
    except Exception as e:
        pipeline["status"] = "error"
        pipeline["error"] = str(e)
        logger.error(f"Pipeline exception: {pipeline_id} — {e}")


def _update_progress(pipeline_id: str, step: str, percentage: int):
    """Pipeline ilerleme callback'i."""
    if pipeline_id in pipelines:
        pipelines[pipeline_id]["current_step"] = step
        pipelines[pipeline_id]["progress"] = percentage
