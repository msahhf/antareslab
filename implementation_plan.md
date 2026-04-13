# AntaresStudio Yeni Web Mimarisi Planı

Eski PyQt6 tabanlı masaüstü uygulamasının yerini alacak, daha esnek, modern ve NVIDIA GPU gücünden tam anlamıyla faydalanabilecek yeni bir Web Sunucu mimarisi önerisi. 

## Önerilen Mimari (Proposed Architecture)

### 1. Backend (Python + FastAPI)
Ağır yük gerektiren tüm işlemler (görüntü işleme, 3D oluşturma) arka uçta (backend) bir sunucu üzerinde koşacaktır.
- **FastAPI**: Yüksek performanslı asenkron API sunucusu. ESP32'den görüntü yakalama veya istemciden gelen taramaları kabul etme görevlerini üstlenir.
- **NVIDIA GPU Desteği (CUDA)**: `rembg` (arka plan temizleme) ve özellik çıkarımı (feature extraction) gibi işlemler için CUDA hızlandırması kullanılarak işlemlerin çok daha kısa sürede tamamlanması sağlanır.
- **3D Pipeline**: Open3D (veya Colmap) entegrasyonu ile nokta bulutu (point cloud) ve mesh (üçgen ağ) oluşturulması bu katmanda yönetilecektir.

### 2. Frontend (Vite + React)
Kullanıcı etkileşimleri için modern, tarayıcı üzerinden çalışan bir web arayüzü oluşturulacaktır. `AntaresDocs` projesiyle tutarlılık sağlamak amacıyla Vite ve React ekosistemi kullanılacaktır.
- Sistemin durumunu izleme (Backend üzerinden ESP32 stream'inin veya loglarının aktarılması).
- Taramaları (Session) listeleyip yönetme.
- Tarama sonuçlarını (PLY/OBJ/STL) 3D Viewer (Three.js / react-three-fiber) kullanarak tarayıcı üzerinden 3 boyutlu şekilde inceleme.

### 3. Klasör / Proje Yapısı
`c:\AntaresLab\AntaresStudio` dizininde yeni yapılandırma:
- **`archive/`**: Eski sistemin tutulduğu arşiv klasörü.
- **`backend/`**: FastAPI, ESP32 İstemcisi, CUDA modelleri ve 3D generator (SfM) pipeline'ı içerecek klasör.
- **`frontend/`**: Yeni web arayüzü için oluşturulacak React projeleri (Vite).

## Önceliklendirme ve Taşıma Sırası (Prioritization)
Projenin tüm özelliklerini tek seferde taşımak yerine modüler bir yaklaşımla, aşama aşama taşıyacağız:
1. **Faz 1: Çekirdek Backend İskeleti ve ESP32 İletişimi**: Görüntü işleme ve 3D pipeline (`antares_studio_final.py` içerisindeki classlar yapılandırılarak) FastAPI'ye async endpointler olarak taşınacak. Görüntü kalite doğrulama (Input QA - blur/kontrast kontrolü) eklenecek.
2. **Faz 2: Frontend Altyapısı (Vite + React)**: Temel arayüz iskeletinin, `react-three-fiber` ile model görüntüleme ekranının ve oturum listelerinin oluşturulması. SSE tabanlı progress endpoint'leri üzerinden veri haberleşmesinin sağlanması.
3. **Faz 3: Canlı Akış, Gelişmiş Kontroller ve İleri Düzey SfM**: ESP32'nin MJPEG stream'ini proxy'leme. Gelişmiş özellik çıkarımı (SuperPoint/LightGlue seçenekleri) ve Bundle Adjustment (COLMAP entegrasyonu) ile pipeline'ın iyileştirilmesi.
4. **Faz 4: Donanım ve Sensör Entegrasyonları (Ar-Ge)**: 
   - **Tof Sensörü (VL53L1X)**: Ölçek recovery (scale recovery) ve otomatik ölçek faktörü ile gerçek boyutlu mesh elde edilmesi.
   - **IMU (MPU-6050)**: Platform eğiminin (< 2°) takibi ve nokta bulutunun yere dik hizalanması.
   - **Motor Kontrolü**: Mikro-adım (DRV8825/TMC2209) ve optik/hall encoder geri bildirimi.

## Planlanan Doğrulama (Verification Plan)
- **Manuel Arka Uç Testi**: Swagger arayüzü (FastAPI dokümantasyonu) üzerinden test görüntüsü yüklenip rembg ve mesh çıkarma endpointlerinin denenmesi.
- **Arayüz Testi**: Next.js geliştirme sunucusu başlatılıp tarayıcı üzerinden modelin görüntülenip görüntülenmediğinin test edilmesi.
