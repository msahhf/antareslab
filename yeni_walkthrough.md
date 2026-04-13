# AntaresStudio IoT v2.1 - Production Ready Walkthrough

## Uygulanan 5 Kategori

---

### 1. Fotogrametri Kalite Optimizasyonu ve Kalıcı Hafıza (NVS)

| Dosya | Değişiklik |
|-------|-----------|
| [firmware_esp.ino](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_esp/firmware_esp.ino) | `Preferences.h` ile NVS kalıcı hafıza: quality, framesize, stabilization_ms, warmup_frames |
| [firmware_esp.ino](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_esp/firmware_esp.ino) | `/api/camera/settings` POST endpoint — ayarlar cihaz kapandığında korunur |
| [firmware_esp.ino](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_esp/firmware_esp.ino) | `nvs_stabilizationMs` (varsayılan 800ms): Motor sonrası mekanik sarsıntı sönümleme |
| [esp32_service.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/services/esp32_service.dart) | `CameraSettings` model + `updateCameraSettings()` / `getCameraSettings()` |

**NVS JSON örneği:**
```json
POST /api/camera/settings
{"quality": 10, "framesize": 13, "stabilization_ms": 800, "warmup_frames": 3}
```

---

### 2. Uç Durum (Edge Case) ve Hata Yönetimi

#### 2a. Bağlantı Kopması (Scan sırasında Wi-Fi kesilirse)
| Dosya | Mekanizma |
|-------|-----------|
| [scan_provider.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/providers/scan_provider.dart) | Her 2 adımda `ping()` → bağlantı yoksa `ScanState.paused` |
| [scan_provider.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/providers/scan_provider.dart) | `resumeScan()` — kaldığı adımdan devam |
| [scan_provider.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/providers/scan_provider.dart) | 3 deneme ile fotoğraf çekimi (geçici kesinti koruması) |
| [dashboard_screen.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/screens/dashboard_screen.dart) | Paused kart: sarı renk, "Devam Et" + "İptal" butonları |

#### 2b. Homing (Güç Kesintisi Sonrası Motor Sıfırlama)
| Dosya | Mekanizma |
|-------|-----------|
| [firmware_arduino.ino](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_arduino/firmware_arduino.ino) | `HOME_SW_PIN (D6)`: Hall Effect / Limit switch (aktif LOW, INPUT_PULLUP) |
| [firmware_arduino.ino](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_arduino/firmware_arduino.ino) | `HOME_MAX_STEPS = 2000` güvenlik limiti |
| [firmware_arduino.ino](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_arduino/firmware_arduino.ino) | Fallback: switch bulunamazsa mevcut pozisyon=0 kabul eder |

#### 2c. SD Kart Hatası
| Dosya | Mekanizma |
|-------|-----------|
| [firmware_esp.ino](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_esp/firmware_esp.ino) | `sdErrorCount` sayacı (5 ardışık hata → SD devre dışı) |
| [firmware_esp.ino](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_esp/firmware_esp.ino) | `checkSDHealth()` — 60sn'de bir SD kartı yeniden dener |
| [firmware_esp.ino](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_esp/firmware_esp.ino) | `/api/sd/list` → SD yoksa `{"error":"SD_DISABLED"}` JSON döner |
| [firmware_esp.ino](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_esp/firmware_esp.ino) | `CEK` yanıtı: `OK`, `FAIL`, veya **`SD_ERR`** |
| [firmware_arduino.ino](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_arduino/firmware_arduino.ino) | LCD'de `!! SD KART HATA !!` gösterimi |

---

### 3. İletişim Senkronizasyonu (Race Conditions)

| Dosya | Mekanizma |
|-------|-----------|
| [firmware_esp.ino](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_esp/firmware_esp.ino) | `volatile bool uartBusy` — UART mutex bayrağı |
| [firmware_esp.ino](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_esp/firmware_esp.ino) | `sendArduinoCommand()` — 2sn mutex bekleme, timeout'ta `[ERR,UART_BUSY]` |
| [firmware_esp.ino](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_esp/firmware_esp.ino) | `listenArduinoTriggers()` — `uartBusy`ken atlanır |
| [firmware_esp.ino](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_esp/firmware_esp.ino) | `beginBridge()` / `endBridge()` — mutex ile UART hattı kilitleme |
| [firmware_esp.ino](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_esp/firmware_esp.ino) | Motor komutları için 15sn timeout (R, H, T) |
| [firmware_arduino.ino](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_arduino/firmware_arduino.ino) | `autoScanBusy` flag — otonom tarama sırasında normal komutlar ertelenir |
| [firmware_arduino.ino](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_arduino/firmware_arduino.ino) | `deferredCmd[]` kuyruğu — tarama bitince ertelenmiş komut işlenir |
| [firmware_arduino.ino](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/firmware_arduino/firmware_arduino.ino) | `P` ve `X` acil komutlar — tarama sırasında bile hemen işlenir |
| [esp32_service.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/services/esp32_service.dart) | Motor komutları için 20sn Flutter timeout (`_motorTimeout`) |

---

### 4. Ağ Stabilizasyonu ve Otomatik Yeniden Bağlanma

| Dosya | Mekanizma |
|-------|-----------|
| [device_provider.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/providers/device_provider.dart) | `connect()` — max 3 deneme, exponential backoff (1s, 2s, 4s) |
| [device_provider.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/providers/device_provider.dart) | `_consecutiveFailures` — 5 ardışık polling hatası → `reconnecting` durumu |
| [device_provider.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/providers/device_provider.dart) | `_startReconnect()` — 5sn'de bir otomatik bağlanma denemesi |
| [device_provider.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/providers/device_provider.dart) | `DeviceConnectionState.reconnecting` — sonsuz "connecting" döngüsü yerine |

---

### 5. Backend (Pipeline UX)

| Dosya | Mekanizma |
|-------|-----------|
| [scan_provider.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/providers/scan_provider.dart) | `startPipelineAndMonitor()` — Meshroom başlat + asenkron izle |
| [scan_provider.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/providers/scan_provider.dart) | `_startPipelinePolling()` — 5sn'de bir `getPipelineStatus()` |
| [scan_provider.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/providers/scan_provider.dart) | `ScanState.pipelineRunning` — UI kilitlenmez, progress gösterilir |
| [scan_provider.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/providers/scan_provider.dart) | Pipeline hata/tamamlanma otomatik algılama |
| [scan_provider.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/providers/scan_provider.dart) | `cancelPipeline()` — çalışan pipeline iptal |
| [dashboard_screen.dart](file:///c:/AntaresLab/AntaresStudio/AntaresStudioIoT/app/lib/screens/dashboard_screen.dart) | Pipeline kartı: mavi renk, ilerleme yüzdesi, İptal butonu |

---

## Doğrulama

| Test | Sonuç |
|------|-------|
| `flutter analyze` | ✅ **0 error**, 82 info |
| UART mutex tutarlılığı | ✅ ESP32 `uartBusy` ↔ Arduino `autoScanBusy` |
| NVS field adları | ✅ ESP32 `Preferences` ↔ Flutter `CameraSettings` |
| API endpoint tutarlılığı | ✅ `/api/camera/settings` both sides |
| SD hata akışı | ✅ ESP32 `SD_ERR` → Arduino LCD `!! SD HATA !!` |
| Timeout zinciri | ✅ Flutter 20s > ESP32 15s > Arduino motor time |

---

## Firmware Sürüm Değişiklikleri

| Firmware | Eski | Yeni |
|----|------|------|
| ESP32-CAM | v2.0.0 | **v2.1.0** |
| Arduino Nano | v2.0 | **v2.1** |
