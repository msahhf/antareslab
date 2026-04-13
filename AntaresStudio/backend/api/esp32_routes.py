from fastapi import APIRouter, HTTPException, BackgroundTasks
from pydantic import BaseModel
from typing import Dict, Optional
import httpx
from fastapi.responses import StreamingResponse
from services.esp32_client import Esp32Client, Esp32Error

router = APIRouter(prefix="/api/esp32", tags=["ESP32"])

# Configuration, could be moved to a fastAPI dependency or config file
ESP32_IP = "192.168.4.1" 
esp_client = Esp32Client(ip=ESP32_IP)

class DownloadRequest(BaseModel):
    session_id: str
    count: int
    out_dir: str

@router.get("/ping")
async def ping_esp32():
    try:
        esp_client.ping()
        return {"status": "success", "message": "ESP32 is reachable."}
    except Esp32Error as e:
        raise HTTPException(status_code=503, detail=str(e))

@router.get("/stream")
async def proxy_mjpeg_stream():
    """Proxies the MJPEG stream from the ESP32 camera."""
    stream_url = f"http://{ESP32_IP}:80/stream"
    
    async def fetch_stream():
        async with httpx.AsyncClient() as client:
            try:
                async with client.stream("GET", stream_url) as response:
                    if response.status_code != 200:
                        yield b"Error connecting to stream"
                        return
                    
                    async for chunk in response.aiter_bytes():
                        yield chunk
            except httpx.RequestError as exc:
                print(f"An error occurred while requesting stream: {exc}")
                yield b"Stream disconnected"

    return StreamingResponse(
        fetch_stream(), 
        media_type="multipart/x-mixed-replace; boundary=123456789000000000000987654321" 
        # Boundary might vary depending on ESP32 firmware, but standard is often enough, 
        # or we just let it proxy the headers as-is. Actually, it's safer to proxy the exact headers from ESP32.
    )

@router.get("/scans")
async def get_scan_list():
    try:
        scans = esp_client.get_scan_list()
        return {"status": "success", "scans": scans}
    except Esp32Error as e:
        raise HTTPException(status_code=502, detail=str(e))

def _download_task(session_id: str, count: int, out_dir: str):
    try:
        # In a real app we might want to store download progress in a DB or memory cache for SSE
        esp_client.download_scan(
            session_id=session_id,
            count=count,
            out_dir=out_dir,
            progress=lambda p: print(f"Download Progress: {p}%"),
            log=lambda msg: print(f"ESP32 Log: {msg}")
        )
    except Exception as e:
        print(f"Download failed: {e}")

@router.post("/download")
async def trigger_download(req: DownloadRequest, background_tasks: BackgroundTasks):
    """Triggers download in the background. Future Phase 2 will add SSE to track this."""
    background_tasks.add_task(_download_task, req.session_id, req.count, req.out_dir)
    return {"status": "accepted", "message": "Download started in background."}
