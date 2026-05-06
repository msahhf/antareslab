"""
AntaresStudio IoT - Photos Router v3.0

Features:
- ESP32-CAM direct HTTP upload (bypass Arduino UART)
- SQLite persistence for sessions
- WebSocket progress notifications
- Optimized binary upload handling
"""

import uuid
import time
import logging
from pathlib import Path
from typing import Optional
from datetime import datetime

from fastapi import APIRouter, UploadFile, File, HTTPException, BackgroundTasks, Request, Body
from fastapi.responses import FileResponse, JSONResponse

from app.config import settings
from app.database import get_db, session_repo, log_repo
from app.services.rembg_service import rembg_service
from app.websocket_manager import ws_manager

router = APIRouter()
logger = logging.getLogger("antares.photos")

# Legacy in-memory sessions (for backward compatibility during migration)
sessions: dict = {}


def get_or_create_session(session_id: Optional[str]) -> str:
    """Get existing or create new session ID."""
    if not session_id:
        session_id = str(uuid.uuid4())[:8]
    return session_id


# =============================================================================
# Standard Upload (Flutter/Form-based)
# =============================================================================

@router.post("/upload")
async def upload_photo(
    file: UploadFile = File(...),
    session_id: Optional[str] = None,
):
    """
    Flutter App'ten fotoğraf yükle (multipart/form-data).
    
    - Fotoğraf JPEG formatında olmalıdır.
    - Opsiyonel session_id ile fotoğraflar gruplanır.
    """
    # Dosya tipi kontrolü
    if file.content_type not in ["image/jpeg", "image/png"]:
        raise HTTPException(400, "Sadece JPEG ve PNG kabul edilir.")
    
    # Boyut kontrolü
    content = await file.read()
    size_mb = len(content) / (1024 * 1024)
    if size_mb > settings.MAX_UPLOAD_SIZE_MB:
        raise HTTPException(413, f"Dosya çok büyük: {size_mb:.1f}MB")
    
    # Session yönetimi
    session_id = get_or_create_session(session_id)
    
    # Database'e kaydet
    db = get_db()
    session = session_repo.create_or_get(db, session_id)
    
    # Dosyayı kaydet
    session_dir = settings.UPLOAD_DIR / session_id
    session_dir.mkdir(parents=True, exist_ok=True)
    
    photo_index = session.photo_count
    filename = f"photo_{photo_index:04d}.jpg"
    filepath = session_dir / filename
    
    with open(filepath, "wb") as f:
        f.write(content)
    
    # Database'e fotoğraf kaydet
    photo = session_repo.add_photo(db, session_id, filename, str(filepath), len(content))
    
    # Log
    message = f"Photo uploaded: {session_id}/{filename} ({size_mb:.1f} MB)"
    log_repo.add_log(db, message, "SUCCESS", "photos")
    await ws_manager.broadcast_log(message, "SUCCESS", "photos")
    
    return {
        "success": True,
        "session_id": session_id,
        "photo_index": photo_index,
        "filename": filename,
        "size_mb": round(size_mb, 2),
        "total_photos": session.photo_count,
    }


# =============================================================================
# ESP32-CAM Direct Upload (Binary Payload - Optimized)
# =============================================================================

@router.post("/esp32-direct")
async def upload_esp32_direct(
    request: Request,
    session_id: Optional[str] = None,
    index: Optional[int] = None,
):
    """
    ESP32-CAM'den direkt binary JPEG upload.
    
    OPTIMIZED for ESP32 HTTPClient - accepts raw binary body.
    No multipart/form-data parsing overhead.
    
    Headers:
        X-Session-ID: optional session identifier
        X-Photo-Index: optional photo sequence number
        Content-Type: image/jpeg (optional)
    
    ESP32 C++ Usage:
        String url = "http://192.168.4.2:8000/api/v1/photos/esp32-direct?session_id=abc123&index=0";
        http.begin(url);
        http.addHeader("Content-Type", "image/jpeg");
        int httpCode = http.POST(fb->buf, fb->len);
    """
    try:
        # Read raw binary body
        body = await request.body()
        
        if len(body) == 0:
            raise HTTPException(400, "Empty payload")
        
        if len(body) > settings.MAX_UPLOAD_SIZE_MB * 1024 * 1024:
            raise HTTPException(413, f"Payload too large: {len(body)/1024/1024:.1f}MB")
        
        # Validate JPEG magic bytes
        if not (body[:2] == b'\xff\xd8' or body[:4] == b'\xff\xd8\xff\xe0' or body[:4] == b'\xff\xd8\xff\xe1'):
            # Try to check if it's PNG
            if body[:4] != b'\x89PNG':
                logger.warning(f"Invalid image format, first bytes: {body[:4].hex()}")
                # Still accept it - ESP32 might have quirks
        
        # Session management
        session_id = session_id or str(uuid.uuid4())[:8]
        
        # Database
        db = get_db()
        session = session_repo.create_or_get(db, session_id)
        
        # Determine filename
        if index is not None:
            filename = f"esp32_{index:04d}.jpg"
        else:
            filename = f"esp32_{session.photo_count:04d}.jpg"
        
        # Save file
        session_dir = settings.UPLOAD_DIR / session_id
        session_dir.mkdir(parents=True, exist_ok=True)
        filepath = session_dir / filename
        
        with open(filepath, "wb") as f:
            f.write(body)
        
        # Database record
        photo = session_repo.add_photo(db, session_id, filename, str(filepath), len(body))
        
        # Async notifications
        size_mb = len(body) / (1024 * 1024)
        message = f"ESP32 direct upload: {session_id}/{filename} ({size_mb:.2f}MB)"
        log_repo.add_log(db, message, "SUCCESS", "esp32")
        await ws_manager.broadcast_log(message, "SUCCESS", "esp32")
        
        # JSON response (minimal for ESP32 parsing)
        return JSONResponse({
            "ok": True,
            "sid": session_id,  # Short keys for ESP32
            "idx": session.photo_count - 1,
            "size": len(body),
        })
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"ESP32 upload failed: {e}")
        raise HTTPException(500, f"Upload failed: {str(e)}")


@router.post("/esp32-telemetry")
async def receive_esp32_telemetry(
    request: Request,
):
    """
    ESP32'den telemetry verisi al (binary veya JSON).
    
    Supports two formats:
    1. JSON: {"t": 25.5, "h": 60, "s": 750, "m": "AUTO"}
    2. CSV: "DATA,25.5,60,750,AUTO,0,false,false,0,false"
    
    ESP32 sends CSV format from Arduino UART bridge.
    """
    try:
        body = await request.body()
        content_type = request.headers.get("content-type", "")
        
        db = get_db()
        telemetry_data = {}
        
        # Try JSON first
        if "json" in content_type or body[0:1] == b'{':
            import json
            data = json.loads(body)
            telemetry_data = {
                "temperature": data.get("t") or data.get("temperature"),
                "humidity": data.get("h") or data.get("humidity"),
                "soil_moisture": data.get("s") or data.get("soil_moisture"),
                "mode": data.get("m") or data.get("mode", "STANDBY"),
            }
        else:
            # Parse CSV: DATA,25.5,60,750,AUTO,0,false,false,0,false
            text = body.decode('utf-8', errors='ignore').strip()
            if text.startswith("DATA,"):
                parts = text.split(',')
                if len(parts) >= 5:
                    telemetry_data = {
                        "temperature": float(parts[1]) if parts[1] else None,
                        "humidity": int(parts[2]) if parts[2].isdigit() else None,
                        "soil_moisture": int(parts[3]) if parts[3].isdigit() else None,
                        "mode": parts[4] if len(parts) > 4 else "STANDBY",
                    }
        
        if telemetry_data:
            from app.database import telemetry_repo
            reading = telemetry_repo.save_telemetry(db, source="esp32", **telemetry_data)
            
            # Broadcast via WebSocket
            await ws_manager.broadcast_telemetry(reading.to_dict())
            
            return {"ok": True, "ts": datetime.utcnow().isoformat()}
        
        return {"ok": False, "error": "Could not parse telemetry"}
        
    except Exception as e:
        logger.error(f"ESP32 telemetry parse error: {e}")
        return {"ok": False, "error": str(e)}


# =============================================================================
# Background Removal
# =============================================================================

@router.post("/clean/{session_id}")
async def clean_backgrounds(
    session_id: str,
    background_tasks: BackgroundTasks,
):
    """
    Bir oturumdaki tüm fotoğrafların arka planını rembg ile temizle.
    
    Background task olarak çalışır, WebSocket üzerinden progress bildirilir.
    """
    db = get_db()
    session = db.query(session_repo.model).filter_by(id=session_id).first()
    
    if not session:
        # Fallback to legacy
        if session_id not in sessions:
            raise HTTPException(404, f"Oturum bulunamadı: {session_id}")
    
    source_dir = settings.UPLOAD_DIR / session_id
    output_dir = settings.CLEANED_DIR / session_id
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Update status
    if session:
        session.status = "cleaning"
        db.commit()
    
    if session_id in sessions:
        sessions[session_id]["cleaning_status"] = "processing"
    
    # Background task
    background_tasks.add_task(
        _clean_session_photos_v3,
        session_id,
        source_dir,
        output_dir,
    )
    
    await ws_manager.broadcast_log(
        f"Background removal started for session {session_id}",
        "INFO",
        "photos"
    )
    
    return {
        "success": True,
        "session_id": session_id,
        "status": "processing",
        "message": "Arka plan temizleme başlatıldı.",
    }


async def _clean_session_photos_v3(session_id: str, source_dir: Path, output_dir: Path):
    """Background task: Batch background removal with WebSocket progress."""
    db = get_db()
    
    try:
        photos = session_repo.get_session_photos(db, session_id)
        
        if not photos:
            logger.warning(f"No photos found for session {session_id}")
            return
        
        total = len(photos)
        success_count = 0
        
        for i, photo in enumerate(photos):
            source_path = Path(photo.original_path)
            output_filename = photo.filename.replace(".jpg", "_clean.png").replace(".jpeg", "_clean.png")
            output_path = output_dir / output_filename
            
            success = await rembg_service.remove_background(
                input_path=source_path,
                output_path=output_path,
            )
            
            if success:
                success_count += 1
                photo.cleaned_path = str(output_path)
                photo.cleaned_at = datetime.utcnow()
                db.commit()
            
            # WebSocket progress every 5 photos
            if i % 5 == 0 or i == total - 1:
                progress = (i + 1) / total * 100
                await ws_manager.broadcast_log(
                    f"Cleaning {session_id}: {i+1}/{total} ({progress:.0f}%)",
                    "INFO",
                    "rembg"
                )
        
        # Update session status
        session = db.query(session_repo.model).filter_by(id=session_id).first()
        if session:
            session.status = "cleaned"
            db.commit()
        
        if session_id in sessions:
            sessions[session_id]["cleaning_status"] = "completed"
            sessions[session_id]["cleaned_count"] = success_count
        
        await ws_manager.broadcast_log(
            f"Background removal complete: {success_count}/{total} photos",
            "SUCCESS",
            "photos"
        )
        
    except Exception as e:
        logger.error(f"Cleaning error for {session_id}: {e}")
        if session_id in sessions:
            sessions[session_id]["cleaning_status"] = "error"
            sessions[session_id]["cleaning_error"] = str(e)
        
        await ws_manager.broadcast_log(
            f"Background removal failed for {session_id}: {e}",
            "ERROR",
            "photos"
        )


# =============================================================================
# Session Status & Retrieval
# =============================================================================

@router.get("/status/{session_id}")
async def get_session_status(session_id: str):
    """Oturum durumu ve fotoğraf listesi."""
    db = get_db()
    
    # Try database first
    session = db.query(session_repo.model).filter_by(id=session_id).first()
    if session:
        photos = session_repo.get_session_photos(db, session_id)
        return {
            "session_id": session_id,
            "created_at": session.created_at.isoformat() if session.created_at else None,
            "status": session.status,
            "photo_count": session.photo_count,
            "photos": [p.to_dict() for p in photos],
        }
    
    # Fallback to legacy
    if session_id in sessions:
        return {
            "session_id": session_id,
            **sessions[session_id],
        }
    
    raise HTTPException(404, f"Oturum bulunamadı: {session_id}")


@router.get("/cleaned/{session_id}/{filename}")
async def get_cleaned_photo(session_id: str, filename: str):
    """Temizlenmiş fotoğrafı indir."""
    filepath = settings.CLEANED_DIR / session_id / filename
    if not filepath.exists():
        raise HTTPException(404, "Dosya bulunamadı")
    return FileResponse(filepath, media_type="image/png")


@router.get("/list")
async def list_sessions():
    """Tüm aktif oturumları listele."""
    db = get_db()
    from app.database import Session as SessionModel
    
    sessions_db = db.query(SessionModel).order_by(SessionModel.created_at.desc()).limit(50).all()
    
    return {
        "sessions": [s.to_dict() for s in sessions_db],
        "count": len(sessions_db),
    }
