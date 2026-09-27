import os
import subprocess
import time
from PIL import Image
from rembg import remove

# ================= AYARLAR =================
# ESP32-CAM'den gelen ham fotoğrafların düşeceği klasör
RAW_DIR = os.path.abspath("images")

# Yapay zekanın arkaplanını siyaha boyayıp kaydedeceği klasör (Meshroom burayı okuyacak)
CLEAN_DIR = os.path.abspath("images_raw")

# Çıktıların (3D Modelin) kaydedileceği klasör
OUTPUT_DIR = os.path.abspath("output_3d")

# Meshroom batch executable path (configurable via MESHROOM_BIN env var)
MESHROOM_YOLU = os.environ.get("MESHROOM_BIN", r"meshroom_batch")
# ============================================

def setup_folders():
    for folder in [RAW_DIR, CLEAN_DIR, OUTPUT_DIR]:
        if not os.path.exists(folder):
            os.makedirs(folder)
            print(f"📁 Klasör oluşturuldu: {folder}")

def process_backgrounds():
    print("\n🧹 Adım 1: Yapay Zeka (rembg) ile Arka Plan Temizliği Başlıyor...")
    
    raw_images = [f for f in os.listdir(RAW_DIR) if f.lower().endswith(('.png', '.jpg', '.jpeg'))]
    
    if not raw_images:
        print(f"❌ HATA: '{RAW_DIR}' klasöründe işlenecek fotoğraf yok!")
        return False

    for idx, filename in enumerate(raw_images):
        input_path = os.path.join(RAW_DIR, filename)
        output_path = os.path.join(CLEAN_DIR, f"{os.path.splitext(filename)[0]}.png")
        
        # Eğer zaten temizlenmişi varsa atla (Zaman kazandırır)
        if os.path.exists(output_path):
            continue
            
        print(f"  -> İşleniyor ({idx+1}/{len(raw_images)}): {filename}")
        
        try:
            # Fotoğrafı aç ve arkaplanı sil (Şeffaf döner)
            input_image = Image.open(input_path)
            output_image = remove(input_image)
            
            # Meshroom şeffaflıkta bazen hata verebilir. 
            # Gönderdiğin örnekteki gibi arka planı katı SİYAH yapıyoruz.
            black_background = Image.new("RGB", output_image.size, (0, 0, 0))
            # Şeffaf olan objeyi siyah arkaplanın üzerine yapıştır
            black_background.paste(output_image, mask=output_image.split()[3]) 
            
            black_background.save(output_path, "PNG")
        except Exception as e:
            print(f"    ❌ {filename} işlenirken hata oluştu: {e}")
            
    print("✅ Arka plan temizliği tamamlandı!")
    return True

def start_3d_pipeline():
    setup_folders()
    
    # 1. Aşama: Fotoğrafları temizle
    if not process_backgrounds():
        return
        
    print("\n⚙️ Adım 2: Meshroom Pipeline çalışıyor. Lütfen bekleyin...")
    
    command = [
        MESHROOM_YOLU,
        "--input", CLEAN_DIR,
        "--output", OUTPUT_DIR
    ]

    start_time = time.time()

    try:
        process = subprocess.run(command, check=True)
        end_time = time.time()
        elapsed_time = (end_time - start_time) / 60
        
        print("\n--------------------------------------------------")
        print(f"🎉 İŞLEM BAŞARIYLA TAMAMLANDI! (Süre: {elapsed_time:.1f} dakika)")
        print(f"📦 3D Model: {OUTPUT_DIR} klasörünün içinde.")
        
    except subprocess.CalledProcessError as e:
        print("\n❌ HATA: Meshroom işlemi sırasında bir çökme yaşandı!")
        print(f"Detay: {e}")

if __name__ == "__main__":
    start_3d_pipeline()