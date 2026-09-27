"""
AntaresStudio IoT Backend - PyInstaller Entry Point

Bu dosya PyInstaller tarafından kullanılan giriş noktasıdır.
Doğrudan çalıştırıldığında uvicorn sunucusunu başlatır.
"""

import os
import sys

# PyInstaller bundle'ında çalışıyorsak, sys._MEIPASS'i pathex'e ekle
if getattr(sys, 'frozen', False):
    # PyInstaller bundle
    base_path = sys._MEIPASS
    os.chdir(os.path.dirname(sys.executable))
    
    # data dizinlerini oluştur
    for d in ['data/uploads', 'data/cleaned', 'data/output', 
              'data/meshroom', 'data/meshroom_cache', 'data/models']:
        os.makedirs(d, exist_ok=True)

import uvicorn
from app.main import app

if __name__ == "__main__":
    uvicorn.run(
        app,
        host="127.0.0.1",
        port=8000,
        log_level="info",
        access_log=False,
    )
