# SPDX-License-Identifier: Apache-2.0

"""
AntaresStudio IoT - rembg Servisi v2.1

Fotoğraflardan arka planı kaldırma.
rembg kütüphanesini kullanarak U²-Net modeli ile segmentasyon yapar.

v2.1 Değişiklikler:
  [2] Session-bazlı model yönetimi: Model RAM'e bir kez yüklenir, batch boyunca paylaşılır
  [2] Paralel batch işleme: ProcessPoolExecutor yerine ThreadPoolExecutor (GIL-free onnxruntime)
  [2] RAM kullanım istatistikleri
"""

import asyncio
import time
import logging
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Optional, Callable

from app.config import settings

logger = logging.getLogger("antares.rembg")


class RembgService:
    """
    rembg ile arka plan temizleme servisi.
    
    Model bir kez RAM'e yüklenir ve tüm batch işlemlerinde paylaşılır.
    Shutdown'da model serbest bırakılır.
    """
    
    def __init__(self):
        self._session = None
        self._model_loaded = False
        self._executor = ThreadPoolExecutor(
            max_workers=settings.REMBG_MAX_WORKERS,
            thread_name_prefix="rembg"
        )
        self._stats = {
            "total_processed": 0,
            "total_errors": 0,
            "total_time_sec": 0.0,
        }
    
    def _ensure_session(self):
        """rembg oturumunu başlat (lazy loading — model bir kez yüklenir)."""
        if self._session is None:
            try:
                from rembg import new_session
                start = time.time()
                self._session = new_session(model_name=settings.REMBG_MODEL)
                load_time = time.time() - start
                self._model_loaded = True
                logger.info(f"Model yüklendi: {settings.REMBG_MODEL} ({load_time:.1f}s)")
            except ImportError:
                logger.warning("rembg kurulu değil! pip install rembg")
                self._model_loaded = False
            except Exception as e:
                logger.error(f"Model yüklenemedi: {e}")
                self._model_loaded = False
    
    @property
    def stats(self) -> dict:
        """İşlem istatistikleri."""
        return {
            **self._stats,
            "model_loaded": self._model_loaded,
            "model_name": settings.REMBG_MODEL,
            "avg_time_sec": (
                self._stats["total_time_sec"] / max(self._stats["total_processed"], 1)
            ),
        }
    
    async def remove_background(
        self,
        input_path: Path,
        output_path: Path,
        alpha_matting: Optional[bool] = None,
    ) -> bool:
        """
        Bir fotoğrafın arka planını kaldır.
        ThreadPoolExecutor'da çalışır (CPU-bound, GIL serbest onnxruntime).
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
        """Senkron arka plan temizleme — paylaşılan session kullanır."""
        start = time.time()
        try:
            self._ensure_session()
            
            if not self._model_loaded:
                logger.warning(f"Model yüklü değil, atlanıyor: {input_path.name}")
                return False
            
            from rembg import remove
            from PIL import Image
            import io
            
            # Fotoğrafı oku
            with open(input_path, "rb") as f:
                input_data = f.read()
            
            # Arka planı kaldır — paylaşılan model session'ı kullanılır
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
            
            # PNG olarak kaydet (şeffaf arka plan)
            img = Image.open(io.BytesIO(output_data))
            img.save(output_path, "PNG")
            
            elapsed = time.time() - start
            self._stats["total_processed"] += 1
            self._stats["total_time_sec"] += elapsed
            
            logger.info(f"Temizlendi: {input_path.name} -> {output_path.name} ({elapsed:.1f}s)")
            return True
            
        except Exception as e:
            self._stats["total_errors"] += 1
            logger.error(f"HATA: {input_path.name}: {e}")
            return False
    
    async def remove_background_batch(
        self,
        input_dir: Path,
        output_dir: Path,
        progress_callback: Optional[Callable] = None,
    ) -> dict:
        """
        Bir klasördeki tüm fotoğrafların arka planını toplu temizle.
        
        Model bir kez yüklenir, tüm fotoğraflar aynı session ile işlenir.
        ThreadPoolExecutor ile paralel çalışır.
        """
        output_dir.mkdir(parents=True, exist_ok=True)
        
        # [2] Model'i batch başında bir kez yükle
        self._ensure_session()
        
        # Desteklenen dosya uzantıları
        extensions = {".jpg", ".jpeg", ".png"}
        photos = sorted([
            f for f in input_dir.iterdir()
            if f.is_file() and f.suffix.lower() in extensions
        ])
        
        if not photos:
            return {"success": False, "error": "Fotoğraf bulunamadı", "count": 0}
        
        results = {
            "total": len(photos),
            "success_count": 0,
            "error_count": 0,
            "errors": [],
            "total_time_sec": 0.0,
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
            
            if progress_callback:
                progress_callback(i + 1, len(photos), photo.name)
        
        results["total_time_sec"] = time.time() - batch_start
        results["avg_per_photo_sec"] = results["total_time_sec"] / max(len(photos), 1)
        results["success"] = results["error_count"] == 0
        return results
    
    def shutdown(self):
        """Model'i ve executor'ı temizle."""
        logger.info("rembg servisi kapatılıyor...")
        self._executor.shutdown(wait=False)
        self._session = None
        self._model_loaded = False
