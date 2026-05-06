"""
AntaresStudio IoT - rembg Service v3.0 (Lazy Loading + Auto-Unload)

RAM-optimized background removal with:
- Lazy model loading (on first /clean request)
- Automatic unloading after inactivity (free up 1.1GB RAM)
- Session reuse during active batch processing
"""

import asyncio
import time
import logging
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Optional, Callable
from dataclasses import dataclass

from app.config import settings
from app.database import get_db, log_repo
from app.websocket_manager import ws_manager

logger = logging.getLogger("antares.rembg")

# Auto-unload timeout (5 minutes of inactivity)
AUTO_UNLOAD_SECONDS = 300


@dataclass
class RembgStats:
    """Processing statistics."""
    total_processed: int = 0
    total_errors: int = 0
    total_time_sec: float = 0.0
    model_load_count: int = 0
    model_last_used: float = 0.0
    model_loaded_at: Optional[float] = None
    
    def to_dict(self) -> dict:
        return {
            "total_processed": self.total_processed,
            "total_errors": self.total_errors,
            "avg_time_sec": self.total_time_sec / max(self.total_processed, 1),
            "model_load_count": self.model_load_count,
            "model_idle_seconds": time.time() - self.model_last_used if self.model_last_used else 0,
            "model_loaded_duration": time.time() - self.model_loaded_at if self.model_loaded_at else 0,
        }


class RembgService:
    """
    RAM-optimized rembg service with lazy loading and auto-unload.
    
    Model only loads when needed and automatically unloads after
    inactivity to free the 1.1GB RAM footprint.
    """
    
    def __init__(self):
        self._session = None
        self._model_loaded = False
        self._unload_timer: Optional[asyncio.Task] = None
        self._stats = RembgStats()
        
        self._executor = ThreadPoolExecutor(
            max_workers=settings.REMBG_MAX_WORKERS,
            thread_name_prefix="rembg"
        )
        
        # Start background unload checker
        self._unload_check_task = asyncio.create_task(self._unload_checker())
    
    def _ensure_session(self) -> bool:
        """
        Lazy load rembg session. Returns True if model is ready.
        """
        if self._session is None:
            try:
                from rembg import new_session
                start = time.time()
                self._session = new_session(model_name=settings.REMBG_MODEL)
                load_time = time.time() - start
                
                self._model_loaded = True
                self._stats.model_load_count += 1
                self._stats.model_loaded_at = time.time()
                self._stats.model_last_used = time.time()
                
                logger.info(f"Model LAZY LOADED: {settings.REMBG_MODEL} ({load_time:.1f}s, load #{self._stats.model_load_count})")
                
                # Log to dashboard
                try:
                    db = get_db()
                    log_repo.add_log(
                        db,
                        f"rembg model loaded ({settings.REMBG_MODEL}, {load_time:.1f}s)",
                        "INFO",
                        "rembg"
                    )
                    # Broadcast via WebSocket
                    asyncio.create_task(ws_manager.broadcast_log(
                        f"rembg model loaded ({load_time:.1f}s)",
                        "INFO",
                        "rembg"
                    ))
                except Exception:
                    pass
                    
            except ImportError:
                logger.error("rembg not installed! pip install rembg")
                return False
            except Exception as e:
                logger.error(f"Model load failed: {e}")
                return False
        
        # Update last used timestamp
        self._stats.model_last_used = time.time()
        return True
    
    def _unload_model(self):
        """Unload model from RAM to free memory."""
        if self._session is not None:
            self._session = None
            self._model_loaded = False
            self._stats.model_loaded_at = None
            
            import gc
            gc.collect()
            
            logger.info(f"Model AUTO-UNLOADED after {AUTO_UNLOAD_SECONDS}s inactivity (RAM freed)")
            
            # Log to dashboard
            try:
                db = get_db()
                log_repo.add_log(db, "rembg model unloaded (RAM freed)", "INFO", "rembg")
                asyncio.create_task(ws_manager.broadcast_log(
                    "rembg model unloaded (RAM freed)",
                    "INFO",
                    "rembg"
                ))
            except Exception:
                pass
    
    async def _unload_checker(self):
        """Background task to check for inactivity and unload model."""
        while True:
            await asyncio.sleep(60)  # Check every minute
            
            if self._model_loaded and self._stats.model_last_used:
                idle_time = time.time() - self._stats.model_last_used
                if idle_time > AUTO_UNLOAD_SECONDS:
                    self._unload_model()
    
    @property
    def stats(self) -> dict:
        """Service statistics."""
        return {
            **self._stats.to_dict(),
            "model_loaded": self._model_loaded,
            "model_name": settings.REMBG_MODEL,
            "auto_unload_seconds": AUTO_UNLOAD_SECONDS,
        }
    
    @property
    def is_model_loaded(self) -> bool:
        """Check if model is currently in RAM."""
        return self._model_loaded
    
    async def remove_background(
        self,
        input_path: Path,
        output_path: Path,
        alpha_matting: Optional[bool] = None,
    ) -> bool:
        """
        Remove background from single image.
        Loads model on-demand if not already in RAM.
        """
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            self._executor,
            self._remove_background_sync,
            input_path,
            output_path,
            alpha_matting,
        )
    
    def _remove_background_sync(
        self,
        input_path: Path,
        output_path: Path,
        alpha_matting: Optional[bool] = None,
    ) -> bool:
        """Synchronous background removal."""
        start = time.time()
        
        try:
            # Lazy load model (only on first use)
            if not self._ensure_session():
                logger.warning(f"Model not available, skipping: {input_path.name}")
                return False
            
            from rembg import remove
            from PIL import Image
            import io
            
            # Read input
            with open(input_path, "rb") as f:
                input_data = f.read()
            
            # Process
            use_alpha = alpha_matting if alpha_matting is not None else settings.REMBG_ALPHA_MATTING
            
            output_data = remove(
                input_data,
                session=self._session,
                alpha_matting=use_alpha,
                alpha_matting_foreground_threshold=240,
                alpha_matting_background_threshold=10,
                alpha_matting_erode_size=10,
                post_process_mask=settings.REMBG_POST_PROCESS,
            )
            
            # Save output
            img = Image.open(io.BytesIO(output_data))
            img.save(output_path, "PNG")
            
            # Update stats
            elapsed = time.time() - start
            self._stats.total_processed += 1
            self._stats.total_time_sec += elapsed
            
            logger.info(f"Cleaned: {input_path.name} ({elapsed:.1f}s)")
            return True
            
        except Exception as e:
            self._stats.total_errors += 1
            logger.error(f"Error processing {input_path.name}: {e}")
            return False
    
    async def remove_background_batch(
        self,
        input_dir: Path,
        output_dir: Path,
        progress_callback: Optional[Callable[[int, int, str], None]] = None,
    ) -> dict:
        """
        Batch process entire directory.
        Model stays loaded throughout batch, then auto-unloads after inactivity.
        """
        # Ensure model is loaded before batch (will stay loaded during processing)
        if not self._ensure_session():
            return {"success": False, "error": "Model could not be loaded", "count": 0}
        
        output_dir.mkdir(parents=True, exist_ok=True)
        
        extensions = {".jpg", ".jpeg", ".png"}
        photos = sorted([
            f for f in input_dir.iterdir()
            if f.is_file() and f.suffix.lower() in extensions
        ])
        
        if not photos:
            return {"success": False, "error": "No photos found", "count": 0}
        
        results = {
            "total": len(photos),
            "success_count": 0,
            "error_count": 0,
            "errors": [],
            "total_time_sec": 0.0,
            "model_was_loaded": True,
        }
        
        batch_start = time.time()
        
        for i, photo in enumerate(photos):
            output_name = photo.stem + "_clean.png"
            output_path = output_dir / output_name
            
            success = await self.remove_background(photo, output_path)
            
            if success:
                results["success_count"] += 1
            else:
                results["error_count"] += 1
                results["errors"].append(photo.name)
            
            # WebSocket progress broadcast
            progress = (i + 1) / len(photos) * 100
            if i % 5 == 0:  # Broadcast every 5 photos to reduce load
                asyncio.create_task(ws_manager.broadcast_log(
                    f"Cleaning progress: {i+1}/{len(photos)} photos ({progress:.0f}%)",
                    "INFO",
                    "rembg"
                ))
            
            if progress_callback:
                progress_callback(i + 1, len(photos), photo.name)
        
        results["total_time_sec"] = time.time() - batch_start
        results["avg_per_photo_sec"] = results["total_time_sec"] / max(len(photos), 1)
        results["success"] = results["error_count"] == 0
        
        # Model will auto-unload after AUTO_UNLOAD_SECONDS of inactivity
        logger.info(f"Batch complete: {results['success_count']}/{results['total']} photos. Model will auto-unload in {AUTO_UNLOAD_SECONDS}s")
        
        return results
    
    def force_unload(self):
        """Manually unload model to free RAM immediately."""
        self._unload_model()
    
    def shutdown(self):
        """Graceful shutdown - unload model and stop executor."""
        logger.info("rembg service shutting down...")
        
        if self._unload_check_task:
            self._unload_check_task.cancel()
        
        self._unload_model()
        self._executor.shutdown(wait=False)
        
        logger.info("rembg service stopped")


# Global service instance
rembg_service = RembgService()
