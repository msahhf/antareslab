# SPDX-License-Identifier: Apache-2.0

"""
AntaresStudio IoT - Meshroom Servisi v2.1

Meshroom CLI ile fotogrametri pipeline yönetimi.
Temizlenmiş fotoğraflardan 3D model üretir.

v2.1 Değişiklikler:
  [2] stdout/stderr parse ile gerçek zamanlı ilerleme takibi
  [3] Otomatik cache cleanup (pipeline bitince GB'larca geçici dosya silinir)
  [4] Model decimation (poligon azaltma) + .glb/.gltf format dönüşümü

Pipeline Aşamaları:
  1. CameraInit
  2. FeatureExtraction (SIFT)
  3. ImageMatching
  4. FeatureMatching
  5. StructureFromMotion (SfM)
  6. PrepareDenseScene
  7. DepthMap Estimation + Filter
  8. Meshing (Poisson)
  9. MeshFiltering
  10. Texturing
  11. [POST] Decimation + Format Dönüşüm (trimesh)
"""

import asyncio
import subprocess
import shutil
import time
import re
import logging
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Optional, Callable

from app.config import settings

logger = logging.getLogger("antares.meshroom")


class MeshroomService:
    """Meshroom fotogrametri pipeline servisi."""
    
    def __init__(self):
        self._process: Optional[subprocess.Popen] = None
        self._cancelled = False
        self._executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="meshroom")
    
    def is_available(self) -> bool:
        """Meshroom'un sistemde kurulu olup olmadığını kontrol et."""
        try:
            result = subprocess.run(
                [settings.MESHROOM_BIN_PATH, "--help"],
                capture_output=True,
                timeout=10,
            )
            return result.returncode == 0
        except (FileNotFoundError, subprocess.TimeoutExpired):
            return False
    
    async def run_pipeline(
        self,
        input_dir: Path,
        output_dir: Path,
        progress_callback: Optional[Callable] = None,
    ) -> dict:
        """
        Meshroom fotogrametri pipeline'ını çalıştır.
        
        Pipeline tamamlandıktan sonra:
          - [4] Model decimation + format dönüşüm
          - [3] Cache cleanup
        """
        self._cancelled = False
        
        if not self.is_available():
            return await self._simulate_pipeline(input_dir, output_dir, progress_callback)
        
        return await self._run_meshroom_batch(input_dir, output_dir, progress_callback)
    
    async def _run_meshroom_batch(
        self,
        input_dir: Path,
        output_dir: Path,
        progress_callback: Optional[Callable] = None,
    ) -> dict:
        """Gerçek Meshroom batch çalıştır."""
        try:
            cache_dir = settings.MESHROOM_CACHE_DIR / output_dir.name
            cache_dir.mkdir(parents=True, exist_ok=True)
            
            cmd = [
                settings.MESHROOM_BIN_PATH,
                "--input", str(input_dir),
                "--output", str(output_dir),
                "--cache", str(cache_dir),
                "--save", str(output_dir / "project.mg"),
            ]
            
            if progress_callback:
                progress_callback("Meshroom başlatılıyor...", 5)
            
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(
                self._executor,
                self._run_subprocess,
                cmd,
                progress_callback,
            )
            
            if result["success"]:
                # [4] Post-processing: Model optimizasyon
                if progress_callback:
                    progress_callback("Model optimizasyonu...", 97)
                
                optimized = await self._optimize_model(
                    result.get("model_path", ""),
                    output_dir,
                )
                if optimized:
                    result["optimized_model"] = optimized
                
                # [3] Cache cleanup
                if settings.AUTO_CLEANUP_CACHE:
                    if progress_callback:
                        progress_callback("Cache temizleniyor...", 99)
                    await self._cleanup_cache(cache_dir)
            
            return result
            
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    def _run_subprocess(self, cmd: list, progress_callback=None) -> dict:
        """
        [2] Subprocess olarak Meshroom çalıştır.
        stdout/stderr'den gerçek zamanlı ilerleme parse eder.
        """
        try:
            self._process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                cwd=str(settings.BASE_DIR),
                bufsize=1,  # Line buffered
            )
            
            # Pipeline adımları ve tahmini ilerleme yüzdeleri
            step_progress = {
                "CameraInit": ("Kamera Başlatma", 5),
                "FeatureExtraction": ("Özellik Çıkarma (SIFT)", 15),
                "ImageMatching": ("Görüntü Eşleştirme", 25),
                "FeatureMatching": ("Özellik Eşleştirme", 35),
                "StructureFromMotion": ("SfM (Yapı ve Hareket)", 50),
                "PrepareDenseScene": ("Yoğun Sahne Hazırlık", 55),
                "DepthMap": ("Derinlik Haritası", 70),
                "DepthMapFilter": ("Derinlik Filtresi", 75),
                "Meshing": ("3D Mesh Oluşturma", 85),
                "MeshFiltering": ("Mesh Filtreleme", 88),
                "Texturing": ("Doku Kaplama", 95),
            }
            
            # [2] Çıktıyı oku, ilerlemeyi ve hataları parse et
            error_lines = []
            current_step = "Başlatılıyor..."
            
            for line in self._process.stdout:
                if self._cancelled:
                    self._process.terminate()
                    return {"success": False, "error": "Pipeline iptal edildi"}
                
                line = line.strip()
                if not line:
                    continue
                
                # Hata satırlarını topla
                if "ERROR" in line or "CRITICAL" in line:
                    error_lines.append(line)
                    logger.error(f"[Meshroom] {line}")
                
                # [2] Meshroom adım çıktılarını parse et
                for step_key, (step_name, pct) in step_progress.items():
                    if step_key in line:
                        current_step = step_name
                        if progress_callback:
                            progress_callback(step_name, pct)
                        logger.info(f"[Meshroom] Adım: {step_name} ({pct}%)")
                        break
                
                # [2] Meshroom'un kendi % ilerleme çıktısını yakala
                # Meshroom bazen "XX%" veya "[XX/YY]" formatında çıktı verir
                pct_match = re.search(r'(\d+)%', line)
                if pct_match:
                    local_pct = int(pct_match.group(1))
                    # Mevcut adımın aralığında lokal ilerleme
                    logger.debug(f"[Meshroom] Lokal ilerleme: {local_pct}%")
            
            self._process.wait()
            
            if self._process.returncode == 0:
                model_path = self._find_output_model(Path(cmd[4]))  # output_dir
                return {
                    "success": True,
                    "model_path": str(model_path) if model_path else "",
                }
            else:
                error_msg = "; ".join(error_lines[-3:]) if error_lines else f"Çıkış kodu: {self._process.returncode}"
                return {
                    "success": False,
                    "error": error_msg,
                }
                
        except Exception as e:
            return {"success": False, "error": str(e)}
        finally:
            self._process = None
    
    # ================================================================
    # [4] Model Optimizasyon (Decimation + Format Dönüşüm)
    # ================================================================
    
    async def _optimize_model(
        self,
        model_path_str: str,
        output_dir: Path,
    ) -> Optional[str]:
        """
        Meshroom çıktısını decimation + format dönüşümü ile optimize et.
        
        - Yüksek poligonlu .obj → düşük poligonlu .glb
        - trimesh kütüphanesi kullanır
        - Flutter'da 3D görüntüleyicide rahat açılabilir boyuta indirir
        """
        if not model_path_str:
            return None
        
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            self._executor,
            self._optimize_model_sync,
            model_path_str,
            output_dir,
        )
    
    def _optimize_model_sync(
        self,
        model_path_str: str,
        output_dir: Path,
    ) -> Optional[str]:
        """Senkron model optimizasyonu."""
        try:
            import trimesh
        except ImportError:
            logger.warning("trimesh kurulu değil! pip install trimesh")
            return None
        
        model_path = Path(model_path_str)
        if not model_path.exists():
            logger.warning(f"Model dosyası bulunamadı: {model_path}")
            return None
        
        try:
            start = time.time()
            logger.info(f"Model optimizasyonu başlıyor: {model_path.name}")
            
            # 1. Modeli yükle
            mesh = trimesh.load(str(model_path), force='mesh')
            original_faces = len(mesh.faces)
            logger.info(f"Orijinal: {original_faces:,} face")
            
            # 2. Decimation (poligon azaltma)
            target = settings.MODEL_TARGET_FACES
            if original_faces > target:
                # Quadric decimation (kalite korumalı)
                ratio = target / original_faces
                mesh = mesh.simplify_quadric_decimation(target)
                logger.info(f"Decimation: {original_faces:,} → {len(mesh.faces):,} face (hedef: {target:,})")
            
            # 3. Format dönüşüm
            output_format = settings.MODEL_OUTPUT_FORMAT.lower()
            output_name = f"model_optimized.{output_format}"
            optimized_path = output_dir / output_name
            
            # Ayrıca models/ dizinine de kopyala
            models_path = settings.MODELS_DIR / output_dir.name
            models_path.mkdir(parents=True, exist_ok=True)
            final_path = models_path / output_name
            
            if output_format in ("glb", "gltf"):
                # GLB/GLTF dışa aktarma
                mesh.export(str(optimized_path), file_type=output_format)
                mesh.export(str(final_path), file_type=output_format)
            else:
                # OBJ fallback
                mesh.export(str(optimized_path), file_type="obj")
                mesh.export(str(final_path), file_type="obj")
            
            elapsed = time.time() - start
            optimized_size_mb = optimized_path.stat().st_size / (1024 * 1024)
            logger.info(
                f"Optimizasyon tamamlandı: {output_name} "
                f"({optimized_size_mb:.1f}MB, {elapsed:.1f}s)"
            )
            
            return str(final_path)
            
        except Exception as e:
            logger.error(f"Model optimizasyon hatası: {e}")
            return None
    
    # ================================================================
    # [3] Cache Cleanup
    # ================================================================
    
    async def _cleanup_cache(self, cache_dir: Path):
        """
        Pipeline tamamlandıktan sonra Meshroom cache'ini temizle.
        GB'larca geçici dosyayı siler.
        """
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, self._cleanup_cache_sync, cache_dir)
    
    def _cleanup_cache_sync(self, cache_dir: Path):
        """Senkron cache temizleme."""
        if not cache_dir.exists():
            return
        
        try:
            total_size = sum(
                f.stat().st_size for f in cache_dir.rglob("*") if f.is_file()
            )
            size_gb = total_size / (1024 ** 3)
            
            shutil.rmtree(str(cache_dir), ignore_errors=True)
            logger.info(f"Cache temizlendi: {cache_dir.name} ({size_gb:.2f} GB)")
        except Exception as e:
            logger.error(f"Cache temizleme hatası: {e}")
    
    async def cleanup_all_caches(self):
        """Tüm Meshroom cache'lerini temizle."""
        cache_base = settings.MESHROOM_CACHE_DIR
        if not cache_base.exists():
            return {"cleaned": 0, "freed_gb": 0}
        
        total_freed = 0
        count = 0
        
        for item in cache_base.iterdir():
            if item.is_dir():
                size = sum(f.stat().st_size for f in item.rglob("*") if f.is_file())
                total_freed += size
                shutil.rmtree(str(item), ignore_errors=True)
                count += 1
        
        freed_gb = total_freed / (1024 ** 3)
        logger.info(f"Tüm cacheler temizlendi: {count} dizin, {freed_gb:.2f} GB")
        return {"cleaned": count, "freed_gb": round(freed_gb, 2)}
    
    async def cleanup_session(self, session_id: str):
        """
        [3] Belirli bir session'ın tüm verilerini temizle.
        Pipeline bitip model aktarıldıktan sonra çağrılır.
        """
        cleaned = []
        
        # Upload dizini
        upload_dir = settings.UPLOAD_DIR / session_id
        if upload_dir.exists():
            shutil.rmtree(str(upload_dir), ignore_errors=True)
            cleaned.append("uploads")
        
        # Cleaned dizini
        cleaned_dir = settings.CLEANED_DIR / session_id
        if cleaned_dir.exists():
            shutil.rmtree(str(cleaned_dir), ignore_errors=True)
            cleaned.append("cleaned")
        
        # Meshroom output dizini (model kopyalandıysa)
        output_dir = settings.OUTPUT_DIR / session_id
        if output_dir.exists():
            shutil.rmtree(str(output_dir), ignore_errors=True)
            cleaned.append("output")
        
        # Cache dizinleri
        for cache_sub in settings.MESHROOM_CACHE_DIR.iterdir():
            if cache_sub.is_dir():
                shutil.rmtree(str(cache_sub), ignore_errors=True)
                cleaned.append(f"cache/{cache_sub.name}")
        
        logger.info(f"Session {session_id} temizlendi: {cleaned}")
        return {"session_id": session_id, "cleaned": cleaned}
    
    # ================================================================
    # Simülasyon (Meshroom yokken)
    # ================================================================
    
    async def _simulate_pipeline(
        self,
        input_dir: Path,
        output_dir: Path,
        progress_callback: Optional[Callable] = None,
    ) -> dict:
        """Geliştirme aşaması: Meshroom yokken pipeline'ı simüle et."""
        steps = [
            ("CameraInit", 5, 1),
            ("Feature Extraction", 15, 3),
            ("Image Matching", 25, 2),
            ("Feature Matching", 35, 3),
            ("Structure from Motion", 50, 5),
            ("Prepare Dense Scene", 55, 2),
            ("Depth Map Estimation", 70, 8),
            ("Depth Map Filtering", 75, 2),
            ("Meshing", 85, 5),
            ("Mesh Filtering", 88, 1),
            ("Texturing", 95, 5),
        ]
        
        for step_name, pct, duration in steps:
            if self._cancelled:
                return {"success": False, "error": "Pipeline iptal edildi"}
            
            if progress_callback:
                progress_callback(step_name, pct)
            
            await asyncio.sleep(duration)
        
        # Simüle edilmiş çıktı
        placeholder = output_dir / "model_placeholder.txt"
        placeholder.write_text(
            "Bu dosya simüle edilmiş bir çıktıdır.\n"
            "Gerçek Meshroom kurulumu ile OBJ/PLY model üretilecektir.\n"
            f"Kaynak fotoğraf sayısı: {len(list(input_dir.iterdir()))}\n"
        )
        
        if progress_callback:
            progress_callback("Tamamlandı", 100)
        
        return {
            "success": True,
            "model_path": str(placeholder),
            "simulated": True,
        }
    
    def _find_output_model(self, output_dir: Path) -> Optional[Path]:
        """Meshroom çıktı klasöründe 3D model dosyasını bul."""
        for ext in [".obj", ".ply", ".abc"]:
            models = list(output_dir.rglob(f"*{ext}"))
            if models:
                # En büyük dosyayı döndür (ana model)
                return max(models, key=lambda p: p.stat().st_size)
        return None
    
    def cancel(self):
        """Çalışan pipeline'ı iptal et."""
        self._cancelled = True
        if self._process:
            self._process.terminate()
    
    def shutdown(self):
        """Executor'ı temizle."""
        self._executor.shutdown(wait=False)
        self.cancel()
