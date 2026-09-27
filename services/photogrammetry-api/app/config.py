# SPDX-License-Identifier: Apache-2.0

"""
AntaresStudio IoT Backend - Konfigürasyon v2.1

v2.1 Değişiklikler:
  [1] ProcessPoolExecutor worker sayısı konfigürasyon
  [3] Session & cache cleanup ayarları
  [4] Model optimizasyon konfigürasyonu (decimation, format dönüşüm)
"""

from pydantic_settings import BaseSettings
from pathlib import Path
import os


class Settings(BaseSettings):
    """Uygulama ayarları."""
    
    # Sunucu
    HOST: str = "0.0.0.0"
    PORT: int = 8000
    DEBUG: bool = True
    
    # Proje Dizinleri
    BASE_DIR: Path = Path(__file__).resolve().parent.parent
    UPLOAD_DIR: Path = BASE_DIR / "data" / "uploads"
    CLEANED_DIR: Path = BASE_DIR / "data" / "cleaned"     # rembg çıktısı
    MESHROOM_DIR: Path = BASE_DIR / "data" / "meshroom"   # Meshroom çalışma dizini
    OUTPUT_DIR: Path = BASE_DIR / "data" / "output"       # 3D model çıktısı
    MODELS_DIR: Path = BASE_DIR / "data" / "models"       # [4] Optimize edilmiş modeller
    
    # rembg Ayarları
    REMBG_MODEL: str = "u2net"          # u2net, u2netp, u2net_human_seg, silueta
    REMBG_ALPHA_MATTING: bool = False   # Daha hassas kenar temizliği
    REMBG_POST_PROCESS: bool = True     # Maske post-processing
    REMBG_MAX_WORKERS: int = 2          # [1] Paralel rembg worker sayısı
    
    # Meshroom Ayarları
    MESHROOM_BIN_PATH: str = os.getenv("MESHROOM_BIN", "meshroom_batch")
    MESHROOM_CACHE_DIR: Path = BASE_DIR / "data" / "meshroom_cache"
    MESHROOM_PIPELINE: str = "photogrammetry"
    
    # [4] Model Optimizasyon Ayarları
    MODEL_TARGET_FACES: int = 50000         # Decimation hedef face sayısı
    MODEL_OUTPUT_FORMAT: str = "glb"        # glb, gltf, obj
    MODEL_KEEP_ORIGINAL: bool = True        # Orijinal modeli de sakla
    
    # [3] Cleanup Ayarları
    AUTO_CLEANUP_CACHE: bool = True         # Pipeline bitince cache otomatik silinsin
    CLEANUP_DELAY_SEC: int = 300            # Cleanup'tan önce bekleme süresi (5dk)
    SESSION_EXPIRE_HOURS: int = 24          # Max oturum ömrü
    
    # Limitler
    MAX_UPLOAD_SIZE_MB: int = 50        # Tek fotoğraf max boyutu
    MAX_PHOTOS_PER_SESSION: int = 100   # Bir oturumda max fotoğraf
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


settings = Settings()

# Dizinleri oluştur
for dir_path in [settings.UPLOAD_DIR, settings.CLEANED_DIR, 
                 settings.MESHROOM_DIR, settings.OUTPUT_DIR,
                 settings.MESHROOM_CACHE_DIR, settings.MODELS_DIR]:
    dir_path.mkdir(parents=True, exist_ok=True)
