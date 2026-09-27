"""
AntaresStudio IoT - Photos Router

Fotoğraf yükleme ve rembg ile arka plan temizleme endpoint'leri.
"""

import uuid
import time
import logging
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, UploadFile, File, HTTPException, BackgroundTasks
from fastapi.responses import FileResponse

from app.config import settings
from app.services.rembg_service import RembgService

router = APIRouter()
rembg_service = RembgService()
logger = logging.getLogger("antares.photos")

# Oturum bazlı fotoğraf takibi
sessions: dict = {}

# Dashboard log helper (imported from main in actual call)
def add_dashboard_log(message: str, level: str = "INFO"):
    """Add log to dashboard if available."""
    try:
        from app.main import add_system_log
        add_system_log(message, level)
    except ImportError:
        pass  # Dashboard not initialized yet


@router.post("/upload")
async def upload_photo(
    file: UploadFile = File(...),
    session_id: Optional[str] = None,
):
    """
    ESP32-CAM'den veya Flutter App'ten fotoğraf yükle.
    
    - Fotoğraf JPEG formatında olmalıdır.
    - Opsiyonel session_id ile fotoğraflar gruplanır.
    - session_id verilmezse yeni bir oturum oluşturulur.
    """
    # Dosya tipi kontrolü
    if file.content_type not in ["image/jpeg", "image/png"]:
        raise HTTPException(400, "Sadece JPEG ve PNG kabul edilir.")
    
    # Boyut kontrolü
    content = await file.read()
    size_mb = len(content) / (1024 * 1024)
    if size_mb > settings.MAX_UPLOAD_SIZE_MB:
        raise HTTPException(413, f"Dosya çok büyük: {size_mb:.1f}MB (max: {settings.MAX_UPLOAD_SIZE_MB}MB)")
    
    # Oturum yönetimi
    if not session_id:
        session_id = str(uuid.uuid4())[:8]
    
    if session_id not in sessions:
        sessions[session_id] = {
            "created_at": time.time(),
            "photo_count": 0,
            "photos": [],
        }
    
    session = sessions[session_id]
    
    if session["photo_count"] >= settings.MAX_PHOTOS_PER_SESSION:
        raise HTTPException(400, f"Oturum limiti aşıldı (max: {settings.MAX_PHOTOS_PER_SESSION})")
    
    # Dosyayı kaydet
    session_dir = settings.UPLOAD_DIR / session_id
    session_dir.mkdir(parents=True, exist_ok=True)
    
    photo_index = session["photo_count"]
    filename = f"photo_{photo_index:04d}.jpg"
    filepath = session_dir / filename
    
    with open(filepath, "wb") as f:
        f.write(content)
    
    session["photo_count"] += 1
    session["photos"].append({
        "index": photo_index,
        "filename": filename,
        "size_bytes": len(content),
        "path": str(filepath),
    })
    
    # Log to dashboard
    add_dashboard_log(
        f"Photo uploaded: {session_id}/{filename} ({size_mb:.1f} MB)", 
        "SUCCESS"
    )
    
    return {
        "success": True,
        "session_id": session_id,
        "photo_index": photo_index,
        "filename": filename,
        "size_mb": round(size_mb, 2),
        "total_photos": session["photo_count"],
    }


@router.post("/clean/{session_id}")
async def clean_backgrounds(
    session_id: str,
    background_tasks: BackgroundTasks,
):
    """
    Bir oturumdaki tüm fotoğrafların arka planını rembg ile temizle.
    
    Background task olarak çalışır, /status endpoint'i ile takip edilir.
    """
    if session_id not in sessions:
        raise HTTPException(404, f"Oturum bulunamadı: {session_id}")
    
    session = sessions[session_id]
    source_dir = settings.UPLOAD_DIR / session_id
    output_dir = settings.CLEANED_DIR / session_id
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Arka planda çalıştır
    session["cleaning_status"] = "processing"
    session["cleaned_count"] = 0
    
    background_tasks.add_task(
        _clean_session_photos,
        session_id,
        source_dir,
        output_dir,
    )
    
    return {
        "success": True,
        "session_id": session_id,
        "status": "processing",
        "total_photos": session["photo_count"],
        "message": "Arka plan temizleme başlatıldı. /status ile takip edin.",
    }


@router.get("/status/{session_id}")
async def get_session_status(session_id: str):
    """Oturum durumu sorgula."""
    if session_id not in sessions:
        raise HTTPException(404, f"Oturum bulunamadı: {session_id}")
    
    return {
        "session_id": session_id,
        **sessions[session_id],
    }


@router.get("/cleaned/{session_id}/{filename}")
async def get_cleaned_photo(session_id: str, filename: str):
    """Temizlenmiş fotoğrafı indir."""
    filepath = settings.CLEANED_DIR / session_id / filename
    if not filepath.exists():
        raise HTTPException(404, "Dosya bulunamadı")
    return FileResponse(filepath, media_type="image/png")


async def _clean_session_photos(session_id: str, source_dir: Path, output_dir: Path):
    """Background task: Tüm fotoğrafların arka planını temizle."""
    session = sessions[session_id]
    
    try:
        for photo in session["photos"]:
            source_path = source_dir / photo["filename"]
            output_filename = photo["filename"].replace(".jpg", "_clean.png")
            output_path = output_dir / output_filename
            
            # rembg ile arka plan temizle
            success = await rembg_service.remove_background(
                input_path=source_path,
                output_path=output_path,
            )
            
            if success:
                session["cleaned_count"] += 1
                photo["cleaned"] = True
                photo["cleaned_path"] = str(output_path)
            else:
                photo["cleaned"] = False
                photo["clean_error"] = "rembg işlemi başarısız"
        
        session["cleaning_status"] = "completed"
        
    except Exception as e:
        session["cleaning_status"] = "error"
        session["cleaning_error"] = str(e)
