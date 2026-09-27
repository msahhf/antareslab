# AntaresStudio IoT - Tam Otonom Dijital İkiz Stüdyosu Refactoring (v2)

## Amaç

Mevcut kod tabanını **"Tam Otonom Dijital İkiz Stüdyosu"** mimarisine tam uyumlu hale getirmek.

## Kullanıcı Geri Bildiriminden Gelen Temel İlkeler

1. **Arduino LCD kalacak**, ancak yalnızca **otonom mod** çalışacak. Menü navigasyonu, manuel mod, hedef sıcaklık ayar menüsü kaldırılacak. DHT22, fan, heater bilgileri LCD'de görünecek ama kullanıcının müdahale şansı minimal olacak. Studio'dan komut geldiğinde ekran duraklatılıp güncelleme gösterilecek.
2. **ESP32 AP modunda** çalışacak. Bilgisayar ESP32'nin ağına bağlanacak, Studio uygulaması bu ağ üzerinden iletişim kuracak.
3. **Otonom mod**: 5 dakikada bir çekim yapılacak, fotoğraflar **SD karta** kaydedilecek. Studio bağlandığında fotoğraflar bilgisayara aktarılacak ve SD karttan silinecek. Fotoğraflar sadece Studio uygulamasında kalacak.

---

## Yeni Mimari Şema

```text
┌──────────────────┐   Wi-Fi AP (192.168.4.1)   ┌──────────────────┐    UART Seri     ┌──────────────┐
│   Flutter App    │ ◄──────────────────────────►│   ESP32-CAM      │◄──────────────►│   Arduino    │
│   (Windows PC)   │   HTTP REST                 │   (AP Gateway)   │  Tetik&Bridge  │ (Motor+LCD)  │
└──────┬───────────┘                             └──────┬───────────┘                └──────────────┘
       │                                                │
       │  localhost:8000                               │ SD Kart (Otonom çekimler)
       ▼                                                │ Aktarım sonrası silinir
┌──────────────────┐                             ┌──────┴───────────┐
│   Backend        │                             │   SD_MMC         │
│   (Python)       │                             │   /IMG_xxx.jpg   │
│   rembg +        │                             └──────────────────┘
│   Meshroom       │
└──────────────────┘
```

**Bağlantı Akışı:**
1. Bilgisayar → ESP32 AP ağına bağlanır (SSID: `ANTARES_KAPSUL_LAB`)
2. Flutter App → `http://192.168.4.1` üzerinden ESP32 ile haberleşir
3. Flutter App → `http://localhost:8000` üzerinden Python Backend ile haberleşir
4. ESP32 → UART üzerinden Arduino'ya komut gönderir

---

## Çalışma Modları

### Mod 1: Otonom Mod (Varsayılan)
- Arduino otomatik olarak 5 dakikada bir tarama döngüsü çalıştırır
- Arduino → ESP32: `CEK` komutu gönderir
- ESP32 fotoğrafı çekip **SD karta** kaydeder
- LCD'de otonom durum bilgileri gösterilir (DHT22, fan, heater, geri sayım)
- Kullanıcı müdahalesi yok

### Mod 2: Studio Bağlantılı Mod
- Flutter App ESP32'ye bağlandığında:
  - SD karttaki fotoğrafları listeler, indirir ve siler
  - Manuel fotoğraf çekimi yapar (doğrudan Wi-Fi aktarım, SD karta kaydetmez)
  - 360° tarama orkestrasyonunu yönetir
  - Arduino'ya komut gönderir (motor kontrolü)
- Arduino LCD'de "STUDIO BAĞLI" yazısı gösterilir, otonom döngü duraklatılır

---

## Proposed Changes

---

### Bileşen 1: Arduino Firmware (Hafifletilmiş Otonom + LCD)

> **İlke**: LCD ve DHT22 kalacak. Sadece otonom mod. Menü navigasyonu, manuel mod kaldırılacak. Studio'dan komut geldiğinde LCD güncellenir.

#### [MODIFY] [main.cpp](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_arduino/src/main.cpp)

Mevcut `firmware_arduino/src/main.cpp` tamamen yeniden yazılacak. Eski `AntaresElectronics/arduino/arduino.ino`'daki kullanışlı kodlar (LCD, DHT22, fan, motor) entegre edilecek.

**Yeni Arduino Yapısı (~300 satır, mevcut 652'den → %54 azalma):**

```
KORUNACAKLAR (arduino.ino'dan):
  ✅ LCD I2C 20x4 (başlatma, özel ikonlar, printLine helper)
  ✅ DHT22 sensör okuma
  ✅ Fan kontrol (SLY, DZ pin'leri)
  ✅ Heater PWM kontrolü
  ✅ Step motor fonksiyonları (moveSteps, motorConstant)
  ✅ Otonom sıcaklık kontrol mantığı (adaptif heater)
  ✅ 5 dakikalık zamanlayıcı ve otonom tarama
  ✅ Giriş ekranı (showIntro)
  ✅ Telemetry gönderimi (sendTelemetryToESP)

KALDIRILACAKLAR:
  ❌ Manuel mod ve mod seçimi (selectMode, isAutonomous toggle)
  ❌ Yatay kart menü sistemi (pageNames, drawMenuCard, handleHorizontalNavigation)
  ❌ Alt menü navigasyonu (openSubMenu, tüm page case'leri)
  ❌ Hedef sıcaklık düzenleme menüsü (editTargetTemp)
  ❌ Buton navigasyonu (btnLeft, btnRight, btnSelect, btnRow - hepsi kalkacak)
  ❌ Dashboard ekranı (showDashboard - artık otonom ekran var)
  ❌ Manuel reboot hotkey (checkGlobalRebootHotkey)
  ❌ Mod değiştirme (checkRowLongPressToggle)

EKLENECEKLER:
  ✅ UART komut parser (<CMD,PARAMS> formatı, firmware_arduino main.cpp'den)
  ✅ Studio mod durumu (studioConnected flag)
  ✅ Studio komutları:
     - <S> → Durum bilgisi gönder [OK,temp,hum,soil,heater,fanSly,fanDz]
     - <H> → Motor Home
     - <R,açı> → Belirli açıya dön
     - <E> → Motor etkinleştir
     - <D> → Motor devre dışı
     - <V,hız> → Motor hızı ayarla
     - <P> → Otonom modu duraklat (Studio bağlandı)
     - <C> → Otonom moda devam et (Studio ayrıldı)
     - <G> → 360 tarama başlat (Arduino motor döndürür, ESP32 tetiklenir)
     - <X> → Tarama durdur
  ✅ LCD güncelleme: Studio komutu geldiğinde LCD "STUDIO BAĞLI" gösterir
  ✅ Otonom LCD ekranı: Sıcaklık, nem, fan durumu, geri sayım (tek ekran, menüsüz)
```

**LCD Ekran Tasarımı (Otonom Mod):**
```
MOD: OTONOM           
T:25.3 H:60% Hdf:24.0
S:ON D:OF H:78%       
Sonraki: 4:32         
```

**LCD Ekran Tasarımı (Studio Bağlı):**
```
>>> STUDIO BAGLI <<<  
T:25.3 H:60%          
Motor Pos: 450        
Komut Bekleniyor...   
```

#### [MODIFY] [platformio.ini](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_arduino/platformio.ini)

- `LiquidCrystal_I2C` ve `DHT sensor library` ekleme
- Pin tanımlarını build_flags'e ekleme

---

### Bileşen 2: ESP32-CAM Firmware (AP Mode + SD Kart + Gateway)

> **İlke**: AP modunda çalışacak. SD kart otonom çekimler için kullanılacak. Studio bağlandığında dosyaları aktarıp silecek. UART ile Arduino'ya komut iletecek.

#### [MODIFY] [main.cpp](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_esp/src/main.cpp)

**Tamamen yeniden yapılandırılacak:**

```
DEĞİŞECEKLER:
  - WiFi.mode(WIFI_STA) → WiFi.softAP() (AP modu)
  - mDNS → kaldırılacak (AP modunda gerekli değil, IP sabit: 192.168.4.1)
  - ArduinoOTA → kaldırılacak (OTA artık HTTP üzerinden yapılır)

YENİ API ENDPOINT'LERİ:
  GET  /api/status           → ESP32 durum bilgisi (JSON)
  GET  /api/capture          → Fotoğraf çek, JPEG olarak döndür (SD kaydetmez)
  GET  /api/stream           → MJPEG canlı akış
  POST /api/arduino/command  → Arduino'ya UART komutu gönder, yanıtı döndür
  GET  /api/arduino/status   → Arduino'dan durum sorgula (<S> gönder)
  GET  /api/sd/list          → SD karttaki fotoğrafları listele (JSON)
  GET  /api/sd/photo/{name}  → SD karttan fotoğraf indir
  DELETE /api/sd/photo/{name} → SD karttan fotoğraf sil
  POST /api/sd/transfer      → Tüm fotoğrafları listele+sil (toplu aktarım)
  POST /api/ota/esp32        → ESP32 firmware güncelleme (HTTP upload)
  POST /api/ota/arduino      → Arduino firmware güncelleme (UART Bridge)

OTONOM FOTOĞRAF ÇEKİMİ:
  - Arduino'dan UART üzerinden "CEK" komutu geldiğinde:
    1. Kamera ile fotoğraf çek
    2. SD karta kaydet (/IMG_{timestamp}.jpg)
    3. Arduino'ya "OK" yanıtı gönder
  - loop() içinde UART dinleme
  
360 TARAMA DESTEĞI:
  - Arduino'dan "360_START" geldiğinde: scan modu aç
  - Arduino'dan "CEK" geldiğinde: /360_{session}_{count}.jpg olarak kaydet
  - Arduino'dan "360_END" geldiğinde: scan modu kapat
```

#### [MODIFY] [config.h](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_esp/src/config.h)

```diff
- #define WIFI_SSID          "YOUR_WIFI_SSID"
- #define WIFI_PASSWORD      "YOUR_WIFI_PASSWORD"
+ #define AP_SSID            "ANTARES_KAPSUL_LAB"
+ #define AP_PASSWORD        "CHANGE_THIS_PASSWORD"

- #define MDNS_HOSTNAME      "antares-scanner"
- #define MDNS_SERVICE_NAME  "_antares"
- #define MDNS_SERVICE_PROTO "_tcp"
- #define MDNS_SERVICE_PORT  80
+ // AP modunda sabit IP: 192.168.4.1

- #define OTA_PASSWORD       "YOUR_OTA_PASSWORD"
- #define OTA_PORT           3232
+ // OTA artık HTTP endpoint üzerinden

- #define BACKEND_HOST       "192.168.1.100"
- #define BACKEND_PORT       8000
- #define BACKEND_UPLOAD_PATH "/api/v1/photos/upload"
+ // Backend'e fotoğraf gönderme ESP32'nin işi değil, Flutter yapar

+ // SD Kart
+ #define SD_CARD_ENABLED    true
```

#### [MODIFY] [camera_manager.h](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_esp/src/camera_manager.h)

- `captureToSD(const char* filename)` fonksiyonu ekleme — fotoğrafı çekip SD karta kaydet
- `captureToBuffer()` mevcut `capture()` zaten bunu yapıyor, korunacak
- Warmup frame discard (ilk 3 frame'i at) — eski esp32.ino'dan alınacak

#### [MODIFY] [uart_bridge.h](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_esp/src/uart_bridge.h)

Bridge moduna ek olarak **normal komut modu** ekleme:
- `sendCommand(const char* cmd)` → Arduino'ya `<cmd>` gönder
- `readResponse(char* buffer, size_t maxLen, uint32_t timeoutMs)` → Yanıt oku
- `listenForTrigger()` → Arduino'dan gelen `CEK`, `360_START`, `360_END` komutlarını dinle

#### [MODIFY] [platformio.ini](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_esp/platformio.ini)

```diff
- lib_deps =
-     ESP32 BLE Arduino
-     ArduinoJson@^6.21.0
-     ESPAsyncWebServer
-     AsyncTCP
+ lib_deps =
+     ArduinoJson@^6.21.0
+     ESPAsyncWebServer
+     AsyncTCP
+     SD_MMC

- upload_protocol = espota
- upload_port = antares-scanner.local
+ ; OTA artık HTTP endpoint üzerinden yapılır
+ ; upload_protocol = espota
```

---

### Bileşen 3: Flutter Windows Desktop App (Merkezi Kontrol)

> **İlke**: ESP32 AP'sine bağlı bilgisayardan çalışır. SD kart yönetimi, tarama orkestrasyon, fotoğraf aktarımı.

#### [MODIFY] [device_provider.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/providers/device_provider.dart)

**SensorData güncellemesi:**
```diff
- final int lightLevel;      // Kaldır (sensör yok)
- final double distance;     // Kaldır (sensör yok)
+ final int soilMoisture;    // Toprak nem ADC (arduino'dan)
+ final int heaterPower;     // Isıtıcı gücü (0-255)
+ final bool fanSly;         // Salyangoz fan durumu
+ final bool fanDz;          // Düz fan durumu
+ final String mode;         // OTONOM / STUDIO
```

**ESP32 host sabit olacak:**
```diff
- String get espHost => _connectedDevice?.host ?? 'antares-scanner.local';
+ static const String espHost = '192.168.4.1';
```

**Yeni metodlar:**
- `capturePhoto()` → `GET /api/capture` → `Uint8List` JPEG döndür
- `sendArduinoCommand(String cmd)` → `POST /api/arduino/command`
- `getArduinoStatus()` → Arduino sensör verilerini al
- `pauseAutonomous()` → Arduino'ya `<P>` gönder (otonom duraklat)
- `resumeAutonomous()` → Arduino'ya `<C>` gönder (otonom devam)

#### [NEW] [scan_provider.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/providers/scan_provider.dart)

Tarama orkestrasyon durumu yöneten provider:
- **Durum**: idle, connecting, homing, scanning, transferring, completed, error
- **İlerleme**: currentStep, totalSteps, currentAngle
- **Yapılandırma**: numPhotos (varsayılan 8), stepAngle (varsayılan 45°), stabilizationDelay
- **Tarama akışı** (Flutter merkezli):
  ```
  1. Arduino'ya <P> gönder (otonom duraklat)
  2. Arduino'ya <H> gönder (Home)
  3. Döngü (i = 0..numPhotos):
     a. ESP32'den GET /api/capture → JPEG al
     b. JPEG'i local dizine kaydet
     c. Arduino'ya <R,{i*stepAngle}> gönder (döndür)
     d. Stabilizasyon bekle (500ms)
  4. Arduino'ya <C> gönder (otonom devam)
  5. Tamamlandı bildir
  ```
- **SD Kart aktarım akışı**:
  ```
  1. GET /api/sd/list → fotoğraf listesi
  2. Her fotoğraf için GET /api/sd/photo/{name} → indir
  3. Her indirilen için DELETE /api/sd/photo/{name} → sil
  4. Local dizine kaydet
  ```

#### [NEW] [esp32_service.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/services/esp32_service.dart)

ESP32 HTTP API istemcisi:
- `getStatus()` → `/api/status` (JSON)
- `capturePhoto()` → `/api/capture` → `Uint8List` JPEG
- `getStreamUrl()` → `http://192.168.4.1/api/stream`
- `sendArduinoCommand(String cmd)` → `/api/arduino/command`
- `getArduinoStatus()` → `/api/arduino/status`
- `listSDPhotos()` → `/api/sd/list` → `List<SDPhoto>`
- `downloadSDPhoto(String name)` → `/api/sd/photo/{name}` → `Uint8List`
- `deleteSDPhoto(String name)` → `/api/sd/photo/{name}` (DELETE)
- `transferAllPhotos()` → Toplu indir + sil
- `uploadEspFirmware(Uint8List)` → `/api/ota/esp32`
- `uploadArduinoFirmware(Uint8List)` → `/api/ota/arduino`

#### [NEW] [backend_service.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/services/backend_service.dart)

Python Backend HTTP istemcisi (localhost:8000):
- `uploadPhoto(Uint8List jpeg, String sessionId)`
- `cleanBackgrounds(String sessionId)`
- `getSessionStatus(String sessionId)`
- `startPipeline(String sessionId)`
- `getPipelineStatus(String pipelineId)`

#### [MODIFY] [dashboard_screen.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/screens/dashboard_screen.dart)

- Sensör kartları güncelleme: Sıcaklık, Nem, Toprak Nem, Isıtıcı Gücü
- Fan durum göstergeleri (SLY, DZ)
- Canlı kamera implementasyonu: `Image.network('http://192.168.4.1/api/stream')`
- Quick Action butonları implement:
  - "360° Tarama" → ScanProvider.startScan()
  - "Tek Fotoğraf" → capturePhoto() → göster
  - "Motor Home" → sendArduinoCommand('H')
  - "SD Aktarım" → ScanProvider.transferFromSD()

#### [MODIFY] [main.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/main.dart)

- `ScanProvider` ekle (MultiProvider'a)
- Windows masaüstüne uygun boyut ayarı

#### [MODIFY] [pubspec.yaml](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/pubspec.yaml)

- `path` paketi ekle (dosya yolu yönetimi)

---

### Bileşen 4: Python Backend (Minimal Değişiklik)

#### [MODIFY] [requirements.txt](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/backend/requirements.txt)

- `pydantic-settings>=2.0.0` ekleme

> Backend kodu büyük ölçüde doğru. Fotoğraflar artık Flutter App'ten gelecek (ESP32'den değil), bu zaten mevcut upload endpoint'i ile uyumlu.

---

### Bileşen 5: Eski Kodlar

#### [NO CHANGE] `AntaresElectronics/arduino/arduino.ino` ve `esp32/esp32.ino`
- Dokunulmayacak, arşiv/referans olarak kalacak
- Kullanışlı kod parçaları (LCD helper'lar, DHT22 kontrol mantığı, motor fonksiyonları) yeni firmware'e entegre edilecek

---

## Veri Akışı Detayı

### Otonom Çalışma (Studio Bağlı Değil)
```
Arduino (5dk timer)
  ↓ UART: "CEK"
ESP32-CAM
  → Fotoğraf çek
  → SD karta kaydet (/IMG_1713045600.jpg)
  ↓ UART: "OK"
Arduino
  → LCD: "FOTO: OK | Sonraki: 4:59"
  → Motor 45° döndür (otonom tarama)
```

### Studio Bağlantılı Çalışma
```
Flutter App (PC, ESP32 AP'sine bağlı)
  │
  ├── GET  /api/status          → ESP32 durum (heap, psram, rssi)
  ├── GET  /api/arduino/status  → Arduino durum (temp, hum, fan, heater)
  ├── GET  /api/capture         → Tek fotoğraf çek (JPEG, SD'ye kaydetmez)
  ├── GET  /api/stream          → Canlı görüntü (MJPEG)
  ├── POST /api/arduino/command → Motor/kontrol komutu
  │     body: {"cmd": "R,90.0"}
  │     → ESP32 UART: "<R,90.0>"
  │     → Arduino yanıtı: "[OK,POS,90.0]"
  │     → HTTP response: {"success": true, "response": "[OK,POS,90.0]"}
  │
  ├── GET  /api/sd/list         → SD karttaki fotoğraf listesi
  │     → {"photos": ["IMG_001.jpg", "IMG_002.jpg"], "count": 2}
  ├── GET  /api/sd/photo/IMG_001.jpg → Fotoğrafı indir
  ├── DELETE /api/sd/photo/IMG_001.jpg → Fotoğrafı SD'den sil
  │
  └── (Localhost) POST /api/v1/photos/upload → Backend'e fotoğraf yükle
```

### 360° Tarama Orkestrasyon
```
Flutter App:
  1. POST /api/arduino/command {"cmd": "P"}     ← Otonom duraklat
  2. POST /api/arduino/command {"cmd": "H"}     ← Motor Home
  3. for i in 0..7:
     a. GET  /api/capture                       ← JPEG al (SD'ye kaydetmez)
     b. POST localhost:8000/api/v1/photos/upload ← Backend'e yükle
     c. POST /api/arduino/command {"cmd": "R,{i*45}"} ← Motor döndür
     d. sleep(500ms)                             ← Stabilizasyon
  4. POST /api/arduino/command {"cmd": "C"}     ← Otonom devam
```

---

## Donanım Bağlantıları (Doğrulama)

| ESP32-CAM Pin | Arduino Pin | Açıklama         |
|---------------|-------------|------------------|
| GPIO 14 (TX)  | RX          | UART Data        |
| GPIO 15 (RX)  | TX          | UART Data        |
| GPIO 12       | RESET       | Arduino Reset    |
| GND           | GND         | Ortak ground     |

| Arduino Pin | Bileşen     | Açıklama          |
|-------------|-------------|--------------------|
| D10         | DHT22       | Sıcaklık/Nem       |
| A0          | Toprak Nem  | Analog okuma       |
| D11         | SLY Fan     | Salyangoz fan      |
| D13         | DZ Fan      | Düz fan            |
| D5          | Heater      | Isıtıcı (PWM)     |
| D9          | STEP        | Step motor adım    |
| D8          | DIR         | Step motor yön     |
| D7          | ENA         | Step motor enable  |

---

## Dosya Değişiklik Özeti

| Dosya | İşlem | Açıklama |
|-------|-------|----------|
| `firmware_arduino/src/main.cpp` | **YENİDEN YAZ** | 652→~300 satır. Sadece otonom, LCD, UART komut |
| `firmware_arduino/platformio.ini` | **GÜNCELLE** | DHT, LCD kütüphaneleri ekle |
| `firmware_esp/src/main.cpp` | **YENİDEN YAZ** | AP mod, SD kart yönetimi, Arduino komut API |
| `firmware_esp/src/config.h` | **GÜNCELLE** | AP ayarları, SD kart, mDNS/OTA kaldır |
| `firmware_esp/src/camera_manager.h` | **GÜNCELLE** | SD kaydetme fonksiyonu ekle |
| `firmware_esp/src/uart_bridge.h` | **GÜNCELLE** | Normal komut modu + trigger dinleme ekle |
| `firmware_esp/platformio.ini` | **GÜNCELLE** | BLE kaldır, SD_MMC ekle, OTA kaldır |
| `app/lib/providers/device_provider.dart` | **GÜNCELLE** | SensorData, sabit IP, yeni metodlar |
| `app/lib/providers/scan_provider.dart` | **YENİ** | Tarama orkestrasyon + SD aktarım |
| `app/lib/services/esp32_service.dart` | **YENİ** | ESP32 HTTP API istemcisi |
| `app/lib/services/backend_service.dart` | **YENİ** | Backend HTTP istemcisi |
| `app/lib/screens/dashboard_screen.dart` | **GÜNCELLE** | Sensör kartları, quick action'lar |
| `app/lib/main.dart` | **GÜNCELLE** | ScanProvider ekleme |
| `app/pubspec.yaml` | **GÜNCELLE** | path paketi |
| `backend/requirements.txt` | **GÜNCELLE** | pydantic-settings |

**Toplam: 15 dosya (4 yeni, 11 güncelleme)**

---

## Verification Plan

### Derleme Testleri
1. `firmware_arduino/` → `pio run -e nanoatmega328` derleme kontrolü
2. `firmware_esp/` → `pio run -e esp32cam` derleme kontrolü  
3. `app/` → `flutter analyze` Dart analiz kontrolü

### Kod Tutarlılık Kontrolü
- UART komut formatı: Arduino parser `<CMD>` ↔ ESP32 sender `<CMD>`
- API endpoint isimleri: ESP32 handler ↔ Flutter service
- JSON field isimleri: ESP32 response ↔ Flutter model

### Manuel Doğrulama
- Kullanıcı gerçek donanımda test edecek
