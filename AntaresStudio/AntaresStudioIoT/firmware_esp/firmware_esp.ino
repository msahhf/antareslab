// =====================================================================
// AntaresStudio IoT - ESP32-CAM Firmware v2.1 (Production Ready)
// =====================================================================
// Değişiklik v2.1:
//   [1] NVS kalıcı kamera ayarları (Preferences.h)
//   [2] /api/camera/settings POST endpoint
//   [3] UART senkronizasyon mutex (race condition koruması)
//   [4] SD kart hata yönetimi (çökmez, hata kodu döner)
//   [5] Dinamik stabilizasyon bekleme süresi (NVS'den okunur)
//   [6] SD sağlık kontrolü (periyodik)
// =====================================================================

#include "esp_camera.h"
#include <WiFi.h>
#include "esp_http_server.h"
#include "FS.h"
#include "SD_MMC.h"
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"
#include <ArduinoJson.h>
#include <Update.h>
#include <Preferences.h>

// ===================== AYARLAR =====================

// AP Modu
const char* AP_SSID      = "ANTARES_KAPSUL_LAB";
const char* AP_PASSWORD   = "12345678";

// UART Bridge Pin'leri (Arduino programlama)
#define UART_TX_PIN         14   // ESP32 TX -> Arduino RX
#define UART_RX_PIN         15   // ESP32 RX -> Arduino TX
#define ARDUINO_RESET_PIN   12   // ESP32 -> Arduino RESET

// Kamera Pin'leri (AI-Thinker)
#define PWDN_GPIO_NUM    32
#define RESET_GPIO_NUM   -1
#define XCLK_GPIO_NUM     0
#define SIOD_GPIO_NUM    26
#define SIOC_GPIO_NUM    27
#define Y9_GPIO_NUM      35
#define Y8_GPIO_NUM      34
#define Y7_GPIO_NUM      39
#define Y6_GPIO_NUM      36
#define Y5_GPIO_NUM      21
#define Y4_GPIO_NUM      19
#define Y3_GPIO_NUM      18
#define Y2_GPIO_NUM       5
#define VSYNC_GPIO_NUM   25
#define HREF_GPIO_NUM    23
#define PCLK_GPIO_NUM    22
#define LED_BUILTIN_PIN  33
#define FLASH_LED_PIN     4

// Bridge zamanlama
#define BRIDGE_RESET_PULSE_MS  100
#define BRIDGE_RESET_WAIT_MS   500
#define BRIDGE_TIMEOUT_MS      60000
#define BRIDGE_CHUNK_SIZE      128

// Firmware versiyon
#define FW_VERSION "2.1.0"

// ===================== GLOBAL DEĞİŞKENLER =====================

httpd_handle_t httpServer = NULL;
httpd_handle_t streamServer = NULL;

// [1] NVS kalıcı ayarlar
Preferences prefs;
int  nvs_jpegQuality      = 10;     // 0-63, düşük=yüksek kalite
int  nvs_frameSize        = 13;     // FRAMESIZE_UXGA = 13
int  nvs_stabilizationMs  = 800;    // Motor sonrası bekleme (ms)
int  nvs_warmupFrames     = 3;      // Isınma frame sayısı

// SD kart durumu
bool sdCardReady = false;
int  sdErrorCount = 0;             // [4] SD ardışık hata sayacı
#define SD_MAX_ERRORS     5        // Bu kadar ardışık hatadan sonra SD devre dışı

// UART senkronizasyon
bool bridgeModeActive = false;
unsigned long bridgeLastActivity = 0;
uint32_t bridgeTotalBytes = 0;
volatile bool uartBusy = false;    // [3] UART mutex bayrağı

// 360 Tarama durumu (Arduino'dan gelen komutlarla)
bool is360Scanning = false;
unsigned long scan360SessionID = 0;
int scan360Count = 0;

// Arduino son telemetri verileri
String ard_temp = "--";
String ard_hum  = "--";
String ard_soil = "--";
String ard_heater = "--";
String ard_fanSly = "0";
String ard_fanDz  = "0";
String ard_mode   = "OTONOM";
String ard_pos    = "0";
String ard_homed  = "0";

// ===================== NVS AYAR YÖNETİMİ =====================

void loadNVSSettings() {
  prefs.begin("camera", true);  // read-only
  nvs_jpegQuality     = prefs.getInt("quality", 10);
  nvs_frameSize       = prefs.getInt("framesize", 13);
  nvs_stabilizationMs = prefs.getInt("stab_ms", 800);
  nvs_warmupFrames    = prefs.getInt("warmup", 3);
  prefs.end();
  Serial.printf("[NVS] Yüklendi: Q=%d, FS=%d, Stab=%dms, Warmup=%d\n",
    nvs_jpegQuality, nvs_frameSize, nvs_stabilizationMs, nvs_warmupFrames);
}

void saveNVSSettings() {
  prefs.begin("camera", false);  // read-write
  prefs.putInt("quality", nvs_jpegQuality);
  prefs.putInt("framesize", nvs_frameSize);
  prefs.putInt("stab_ms", nvs_stabilizationMs);
  prefs.putInt("warmup", nvs_warmupFrames);
  prefs.end();
  Serial.println("[NVS] Ayarlar kaydedildi.");
}

// Kamera ayarlarını runtime'da güncelle
void applyCameraSettings() {
  sensor_t *s = esp_camera_sensor_get();
  if (!s) return;
  s->set_quality(s, nvs_jpegQuality);
  s->set_framesize(s, (framesize_t)nvs_frameSize);
  Serial.printf("[Camera] Ayarlar uygulandı: Q=%d, FS=%d\n", nvs_jpegQuality, nvs_frameSize);
}

// ===================== KAMERA BAŞLATMA =====================

bool initCamera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer   = LEDC_TIMER_0;
  config.pin_d0       = Y2_GPIO_NUM;
  config.pin_d1       = Y3_GPIO_NUM;
  config.pin_d2       = Y4_GPIO_NUM;
  config.pin_d3       = Y5_GPIO_NUM;
  config.pin_d4       = Y6_GPIO_NUM;
  config.pin_d5       = Y7_GPIO_NUM;
  config.pin_d6       = Y8_GPIO_NUM;
  config.pin_d7       = Y9_GPIO_NUM;
  config.pin_xclk     = XCLK_GPIO_NUM;
  config.pin_pclk     = PCLK_GPIO_NUM;
  config.pin_vsync    = VSYNC_GPIO_NUM;
  config.pin_href     = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn     = PWDN_GPIO_NUM;
  config.pin_reset    = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;

  if (psramFound()) {
    config.frame_size   = (framesize_t)nvs_frameSize;
    config.jpeg_quality = nvs_jpegQuality;
    config.fb_count     = 2;
    Serial.printf("[Camera] PSRAM bulundu. FS=%d, Q=%d\n", nvs_frameSize, nvs_jpegQuality);
  } else {
    config.frame_size   = FRAMESIZE_SVGA;
    config.jpeg_quality = 12;
    config.fb_count     = 1;
    Serial.println("[Camera] PSRAM yok, SVGA.");
  }

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("[Camera] HATA: 0x%x\n", err);
    return false;
  }

  // Kamera sensor ayarları
  sensor_t *s = esp_camera_sensor_get();
  if (s) {
    s->set_brightness(s, 0);
    s->set_contrast(s, 0);
    s->set_saturation(s, 0);
    s->set_whitebal(s, 1);
    s->set_awb_gain(s, 1);
    s->set_wb_mode(s, 0);
    s->set_exposure_ctrl(s, 1);
    s->set_gain_ctrl(s, 1);
  }
  return true;
}

// ===================== FOTOĞRAF ÇEKİM =====================

// [5] Isınma frame'leri atıp kaliteli çekim yap
camera_fb_t* captureFrame() {
  // Isınma frame'lerini at
  for (int i = 0; i < nvs_warmupFrames; i++) {
    camera_fb_t* fb = esp_camera_fb_get();
    if (fb) esp_camera_fb_return(fb);
    delay(50);
  }
  delay(200);
  return esp_camera_fb_get();
}

// [4] SD karta kaydet — hata yönetimli
bool captureToSD(const char* filename) {
  if (!sdCardReady) {
    Serial.println("[SD] SD kart hazır değil!");
    return false;
  }

  camera_fb_t* fb = captureFrame();
  if (!fb) {
    Serial.println("[Camera] Frame yakalanamadı!");
    return false;
  }

  File file = SD_MMC.open(filename, FILE_WRITE);
  if (!file) {
    Serial.printf("[SD] Dosya açılamadı: %s\n", filename);
    esp_camera_fb_return(fb);
    sdErrorCount++;
    if (sdErrorCount >= SD_MAX_ERRORS) {
      Serial.println("[SD] Çok fazla hata! SD devre dışı.");
      sdCardReady = false;
    }
    return false;
  }

  size_t written = file.write(fb->buf, fb->len);
  file.close();
  esp_camera_fb_return(fb);

  if (written > 0) {
    sdErrorCount = 0;  // Başarılı → hata sayacı sıfırla
    Serial.printf("[SD] Kaydedildi: %s (%u bytes)\n", filename, written);
    return true;
  }
  
  Serial.println("[SD] Yazma hatası!");
  sdErrorCount++;
  if (sdErrorCount >= SD_MAX_ERRORS) {
    Serial.println("[SD] Çok fazla hata! SD devre dışı.");
    sdCardReady = false;
  }
  return false;
}

// [4] SD kart sağlık kontrolü (periyodik)
void checkSDHealth() {
  if (!sdCardReady && sdErrorCount >= SD_MAX_ERRORS) {
    // SD kartı yeniden dene
    Serial.println("[SD] Yeniden başlatma deneniyor...");
    SD_MMC.end();
    delay(500);
    if (SD_MMC.begin("/sdcard", true)) {
      uint64_t cardSize = SD_MMC.cardSize() / (1024 * 1024);
      Serial.printf("[SD] Kart geri geldi: %llu MB\n", cardSize);
      sdCardReady = true;
      sdErrorCount = 0;
    } else {
      Serial.println("[SD] Hala erişilemiyor.");
    }
  }
}

// ===================== ARDUINO UART İLETİŞİM =====================

// Arduino'dan gelen telemetri verisini parse et
void parseArduinoTelemetry(const String& line) {
  if (!line.startsWith("DATA,")) return;

  // DATA,temp,hum,soil,heater,fanSly,fanDz,mode,pos,homed
  int idx = 5;
  String parts[9];
  int partCount = 0;

  for (int i = idx; i <= (int)line.length(); i++) {
    if (i == (int)line.length() || line[i] == ',') {
      parts[partCount] = line.substring(idx, i);
      partCount++;
      idx = i + 1;
      if (partCount >= 9) break;
    }
  }

  if (partCount >= 7) {
    ard_temp   = parts[0];
    ard_hum    = parts[1];
    ard_soil   = parts[2];
    ard_heater = parts[3];
    ard_fanSly = parts[4];
    ard_fanDz  = parts[5];
    ard_mode   = parts[6];
    if (partCount >= 8) ard_pos   = parts[7];
    if (partCount >= 9) ard_homed = parts[8];
  }
}

// [3] Arduino'ya komut gönder — mutex korumalı
String sendArduinoCommand(const char* cmd, uint32_t timeoutMs = 5000) {
  if (bridgeModeActive) return "[ERR,BRIDGE_ACTIVE]";

  // Mutex kontrolü — başka bir UART işlemi devam ediyorsa bekle
  unsigned long waitStart = millis();
  while (uartBusy) {
    if (millis() - waitStart > 2000) {
      Serial.println("[UART] Mutex zaman aşımı!");
      return "[ERR,UART_BUSY]";
    }
    delay(10);
  }
  uartBusy = true;

  // Buffer temizle (eski veriyi at)
  while (Serial2.available()) Serial2.read();

  // Komutu gönder
  Serial2.print("<");
  Serial2.print(cmd);
  Serial2.println(">");
  Serial2.flush();

  Serial.printf("[UART] Gönderildi: <%s>\n", cmd);

  // Yanıt bekle
  String response = "";
  unsigned long start = millis();
  while (millis() - start < timeoutMs) {
    if (Serial2.available()) {
      char c = Serial2.read();
      response += c;
      if (c == '\n') break;
    }
    delay(1);
  }

  response.trim();
  uartBusy = false;  // Mutex serbest bırak

  if (response.length() == 0) {
    Serial.println("[UART] Zaman aşımı, yanıt yok!");
    return "[ERR,TIMEOUT]";
  }

  Serial.printf("[UART] Yanıt: %s\n", response.c_str());
  return response;
}

// [3] Arduino'dan gelen tetik komutlarını dinle — mutex korumalı
void listenArduinoTriggers() {
  if (bridgeModeActive || uartBusy) return;

  while (Serial2.available()) {
    String line = Serial2.readStringUntil('\n');
    line.trim();

    if (line.length() == 0) continue;

    // Telemetri verisi
    if (line.startsWith("DATA,")) {
      parseArduinoTelemetry(line);
      continue;
    }

    // 360 tarama başlangıcı
    if (line == "360_START") {
      is360Scanning = true;
      scan360SessionID = millis();
      scan360Count = 0;
      Serial.println("[Trigger] 360 tarama başladı");
      continue;
    }

    // 360 tarama sonu
    if (line == "360_END") {
      is360Scanning = false;
      Serial.printf("[Trigger] 360 tarama bitti. %d fotoğraf.\n", scan360Count);
      continue;
    }

    // Fotoğraf çekim komutu
    if (line == "CEK") {
      Serial.println("[Trigger] Cekim komutu alindi");

      // [5] Stabilizasyon bekleme (motor sonrası sarsıntı sönümleme)
      delay(nvs_stabilizationMs);

      String filename;
      if (is360Scanning) {
        filename = "/360_" + String(scan360SessionID) + "_" + String(scan360Count) + ".jpg";
        scan360Count++;
      } else {
        filename = "/IMG_" + String(millis()) + ".jpg";
      }

      if (captureToSD(filename.c_str())) {
        Serial2.println("OK");
      } else {
        // [4] SD hata durumunu Arduino'ya bildir
        Serial2.println(sdCardReady ? "FAIL" : "SD_ERR");
      }
      continue;
    }

    // Diğer yanıtlar
    if (line.startsWith("[")) {
      Serial.printf("[Arduino] %s\n", line.c_str());
    }
  }
}

// ===================== UART BRIDGE (Arduino Programlama) =====================

void resetArduino() {
  Serial.println("[Bridge] Arduino RESET...");
  digitalWrite(ARDUINO_RESET_PIN, LOW);
  delay(BRIDGE_RESET_PULSE_MS);
  digitalWrite(ARDUINO_RESET_PIN, HIGH);
  delay(BRIDGE_RESET_WAIT_MS);
  Serial.println("[Bridge] Arduino RESET tamamlandı.");
}

bool beginBridge() {
  // [3] Mutex ile UART hattını kilitle
  unsigned long waitStart = millis();
  while (uartBusy) {
    if (millis() - waitStart > 3000) return false;
    delay(10);
  }
  uartBusy = true;

  Serial.println("[Bridge] Başlatılıyor...");
  bridgeModeActive = true;
  bridgeLastActivity = millis();
  bridgeTotalBytes = 0;

  resetArduino();

  while (Serial2.available()) Serial2.read();

  Serial.println("[Bridge] Bridge modu AKTİF.");
  return true;
}

void endBridge() {
  Serial.printf("[Bridge] Kapatılıyor. Toplam: %u bytes\n", bridgeTotalBytes);
  bridgeModeActive = false;
  uartBusy = false;  // Mutex serbest bırak
  resetArduino();
  Serial.println("[Bridge] Bridge modu KAPALI.");
}

size_t bridgeForwardData(const uint8_t* data, size_t len) {
  if (!bridgeModeActive) return 0;
  bridgeLastActivity = millis();

  size_t totalSent = 0;
  size_t remaining = len;
  while (remaining > 0) {
    size_t chunk = min(remaining, (size_t)BRIDGE_CHUNK_SIZE);
    size_t sent = Serial2.write(data + totalSent, chunk);
    Serial2.flush();
    totalSent += sent;
    remaining -= sent;
    delay(5);
  }
  bridgeTotalBytes += totalSent;
  return totalSent;
}

// ===================== HTTP HANDLER'LAR =====================

// --- GET /api/status ---
static esp_err_t statusHandler(httpd_req_t *req) {
  StaticJsonDocument<512> doc;
  doc["device"]      = "ESP32-CAM";
  doc["firmware"]    = FW_VERSION;
  doc["ip"]          = WiFi.softAPIP().toString();
  doc["clients"]     = WiFi.softAPgetStationNum();
  doc["bridge_mode"] = bridgeModeActive;
  doc["sd_card"]     = sdCardReady;
  doc["sd_errors"]   = sdErrorCount;      // [4] SD hata sayısı
  doc["heap_free"]   = ESP.getFreeHeap();
  doc["psram_free"]  = ESP.getFreePsram();
  doc["uptime_sec"]  = millis() / 1000;
  doc["jpeg_quality"]     = nvs_jpegQuality;     // [1] Kamera ayarları
  doc["frame_size"]       = nvs_frameSize;
  doc["stabilization_ms"] = nvs_stabilizationMs;

  String json;
  serializeJson(doc, json);
  httpd_resp_set_type(req, "application/json");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  return httpd_resp_send(req, json.c_str(), json.length());
}

// --- GET /api/arduino/status ---
static esp_err_t arduinoStatusHandler(httpd_req_t *req) {
  StaticJsonDocument<512> doc;
  doc["temp"]       = ard_temp;
  doc["hum"]        = ard_hum;
  doc["soil"]       = ard_soil;
  doc["heater"]     = ard_heater;
  doc["fanSly"]     = ard_fanSly;
  doc["fanDz"]      = ard_fanDz;
  doc["mode"]       = ard_mode;
  doc["position"]   = ard_pos;
  doc["homed"]      = ard_homed;

  String json;
  serializeJson(doc, json);
  httpd_resp_set_type(req, "application/json");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  return httpd_resp_send(req, json.c_str(), json.length());
}

// --- GET /api/capture ---
static esp_err_t captureHandler(httpd_req_t *req) {
  if (bridgeModeActive) {
    httpd_resp_send_err(req, HTTPD_503_SERVICE_UNAVAILABLE, "Bridge modu aktif");
    return ESP_FAIL;
  }

  camera_fb_t* fb = captureFrame();
  if (!fb) {
    httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "Kamera hatasi");
    return ESP_FAIL;
  }

  httpd_resp_set_type(req, "image/jpeg");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  httpd_resp_set_hdr(req, "Content-Disposition", "inline; filename=capture.jpg");
  esp_err_t res = httpd_resp_send(req, (const char*)fb->buf, fb->len);
  esp_camera_fb_return(fb);
  return res;
}

// --- GET /api/stream (MJPEG) ---
static esp_err_t streamHandler(httpd_req_t *req) {
  camera_fb_t *fb = NULL;
  esp_err_t res = ESP_OK;
  char part_buf[128];

  httpd_resp_set_type(req, "multipart/x-mixed-replace; boundary=frame");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");

  while (true) {
    fb = esp_camera_fb_get();
    if (!fb) { res = ESP_FAIL; break; }

    size_t hlen = snprintf(part_buf, sizeof(part_buf),
      "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n", fb->len);

    res = httpd_resp_send_chunk(req, part_buf, hlen);
    if (res != ESP_OK) { esp_camera_fb_return(fb); break; }

    res = httpd_resp_send_chunk(req, (const char*)fb->buf, fb->len);
    esp_camera_fb_return(fb);
    if (res != ESP_OK) break;

    res = httpd_resp_send_chunk(req, "\r\n", 2);
    if (res != ESP_OK) break;
  }
  return res;
}

// --- POST /api/arduino/command ---
static esp_err_t arduinoCommandHandler(httpd_req_t *req) {
  char body[256];
  int received = httpd_req_recv(req, body, sizeof(body) - 1);
  if (received <= 0) {
    httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "Body bos");
    return ESP_FAIL;
  }
  body[received] = '\0';

  StaticJsonDocument<256> inDoc;
  DeserializationError err = deserializeJson(inDoc, body);
  if (err) {
    httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "JSON parse hatasi");
    return ESP_FAIL;
  }

  const char* cmd = inDoc["cmd"];
  if (!cmd) {
    httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "'cmd' alani eksik");
    return ESP_FAIL;
  }

  // [3] Timeout parametresi: motor komutları daha uzun sürebilir
  uint32_t timeout = 5000;
  if (cmd[0] == 'R' || cmd[0] == 'H' || cmd[0] == 'T') {
    timeout = 15000;  // Motor komutları için uzun timeout
  }

  String response = sendArduinoCommand(cmd, timeout);

  StaticJsonDocument<256> outDoc;
  outDoc["success"]  = response.startsWith("[OK");
  outDoc["response"] = response;
  outDoc["cmd"]      = cmd;

  String json;
  serializeJson(outDoc, json);
  httpd_resp_set_type(req, "application/json");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  return httpd_resp_send(req, json.c_str(), json.length());
}

// --- [2] POST /api/camera/settings ---
static esp_err_t cameraSettingsHandler(httpd_req_t *req) {
  char body[256];
  int received = httpd_req_recv(req, body, sizeof(body) - 1);
  if (received <= 0) {
    httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "Body bos");
    return ESP_FAIL;
  }
  body[received] = '\0';

  StaticJsonDocument<256> doc;
  DeserializationError err = deserializeJson(doc, body);
  if (err) {
    httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "JSON parse hatasi");
    return ESP_FAIL;
  }

  // Değerleri güncelle (verilen alanlar güncellenir, verilmeyenler aynı kalır)
  if (doc.containsKey("quality")) {
    nvs_jpegQuality = constrain(doc["quality"].as<int>(), 0, 63);
  }
  if (doc.containsKey("framesize")) {
    nvs_frameSize = constrain(doc["framesize"].as<int>(), 0, 13);
  }
  if (doc.containsKey("stabilization_ms")) {
    nvs_stabilizationMs = constrain(doc["stabilization_ms"].as<int>(), 0, 5000);
  }
  if (doc.containsKey("warmup_frames")) {
    nvs_warmupFrames = constrain(doc["warmup_frames"].as<int>(), 0, 10);
  }

  // NVS'ye kaydet
  saveNVSSettings();

  // Kameraya uygula
  applyCameraSettings();

  // Yanıt
  StaticJsonDocument<256> outDoc;
  outDoc["success"]          = true;
  outDoc["quality"]          = nvs_jpegQuality;
  outDoc["framesize"]        = nvs_frameSize;
  outDoc["stabilization_ms"] = nvs_stabilizationMs;
  outDoc["warmup_frames"]    = nvs_warmupFrames;

  String json;
  serializeJson(outDoc, json);
  httpd_resp_set_type(req, "application/json");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  return httpd_resp_send(req, json.c_str(), json.length());
}

// --- GET /api/sd/list ---
static esp_err_t sdListHandler(httpd_req_t *req) {
  // [4] SD durumunu her zaman döndür, hata varsa hata kodu ver
  StaticJsonDocument<2048> doc;

  if (!sdCardReady) {
    doc["error"]    = sdErrorCount >= SD_MAX_ERRORS ? "SD_DISABLED" : "SD_NOT_FOUND";
    doc["sd_errors"] = sdErrorCount;
    doc["count"]    = 0;
    String json;
    serializeJson(doc, json);
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
    return httpd_resp_send(req, json.c_str(), json.length());
  }

  JsonArray photos = doc.createNestedArray("photos");
  int count = 0;

  File root = SD_MMC.open("/");
  if (root) {
    File file = root.openNextFile();
    while (file) {
      if (!file.isDirectory()) {
        String fname = String(file.name());
        if (fname.endsWith(".jpg") || fname.endsWith(".JPG")) {
          if (fname.startsWith("/")) fname = fname.substring(1);
          JsonObject photo = photos.createNestedObject();
          photo["name"] = fname;
          photo["size"] = file.size();
          count++;
        }
      }
      file = root.openNextFile();
    }
    root.close();
  }
  doc["count"] = count;

  String json;
  serializeJson(doc, json);
  httpd_resp_set_type(req, "application/json");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  return httpd_resp_send(req, json.c_str(), json.length());
}

// --- GET /api/sd/photo?name=xxx ---
static esp_err_t sdPhotoHandler(httpd_req_t *req) {
  if (!sdCardReady) {
    httpd_resp_send_err(req, HTTPD_503_SERVICE_UNAVAILABLE, "SD kart yok");
    return ESP_FAIL;
  }

  char query[128] = {0};
  char filename[128] = {0};
  if (httpd_req_get_url_query_str(req, query, sizeof(query)) == ESP_OK) {
    httpd_query_key_value(query, "name", filename, sizeof(filename));
  }

  if (strlen(filename) == 0) {
    httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "name parametresi eksik");
    return ESP_FAIL;
  }

  String filepath = "/" + String(filename);
  File file = SD_MMC.open(filepath.c_str(), FILE_READ);
  if (!file) {
    httpd_resp_send_err(req, HTTPD_404_NOT_FOUND, "Dosya bulunamadi");
    return ESP_FAIL;
  }

  httpd_resp_set_type(req, "image/jpeg");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");

  uint8_t buffer[4096];
  size_t bytesRead;
  while ((bytesRead = file.read(buffer, sizeof(buffer))) > 0) {
    httpd_resp_send_chunk(req, (const char*)buffer, bytesRead);
  }
  httpd_resp_send_chunk(req, NULL, 0);
  file.close();
  return ESP_OK;
}

// --- DELETE /api/sd/photo?name=xxx ---
static esp_err_t sdDeleteHandler(httpd_req_t *req) {
  if (!sdCardReady) {
    httpd_resp_send_err(req, HTTPD_503_SERVICE_UNAVAILABLE, "SD kart yok");
    return ESP_FAIL;
  }

  char query[128] = {0};
  char filename[128] = {0};
  if (httpd_req_get_url_query_str(req, query, sizeof(query)) == ESP_OK) {
    httpd_query_key_value(query, "name", filename, sizeof(filename));
  }

  if (strlen(filename) == 0) {
    httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "name parametresi eksik");
    return ESP_FAIL;
  }

  String filepath = "/" + String(filename);
  bool success = SD_MMC.remove(filepath.c_str());

  StaticJsonDocument<128> doc;
  doc["success"] = success;
  doc["file"]    = filename;

  String json;
  serializeJson(doc, json);
  httpd_resp_set_type(req, "application/json");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  return httpd_resp_send(req, json.c_str(), json.length());
}

// --- POST /api/ota/esp32 ---
static esp_err_t otaEsp32Handler(httpd_req_t *req) {
  esp_camera_deinit();

  size_t remaining = req->content_len;
  uint8_t buf[1024];
  bool started = false;

  while (remaining > 0) {
    int received = httpd_req_recv(req, (char*)buf, min(remaining, sizeof(buf)));
    if (received <= 0) {
      httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "Alma hatasi");
      return ESP_FAIL;
    }

    if (!started) {
      if (!Update.begin(UPDATE_SIZE_UNKNOWN)) {
        Update.printError(Serial);
        httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "Update baslatilamadi");
        return ESP_FAIL;
      }
      started = true;
    }

    if (Update.write(buf, received) != (size_t)received) {
      Update.printError(Serial);
      httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "Yazma hatasi");
      return ESP_FAIL;
    }

    remaining -= received;
  }

  if (!Update.end(true)) {
    Update.printError(Serial);
    httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "Update bitis hatasi");
    return ESP_FAIL;
  }

  httpd_resp_set_type(req, "application/json");
  httpd_resp_sendstr(req, "{\"success\":true,\"message\":\"ESP32 guncelleme basarili. Yeniden baslatiliyor...\"}");

  delay(1000);
  ESP.restart();
  return ESP_OK;
}

// --- POST /api/ota/arduino ---
static esp_err_t otaArduinoHandler(httpd_req_t *req) {
  if (!beginBridge()) {
    httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "Bridge baslatilamadi (UART mesgul)");
    return ESP_FAIL;
  }

  size_t remaining = req->content_len;
  uint8_t buf[512];

  while (remaining > 0) {
    int received = httpd_req_recv(req, (char*)buf, min(remaining, sizeof(buf)));
    if (received <= 0) break;

    bridgeForwardData(buf, received);
    remaining -= received;
  }

  endBridge();

  httpd_resp_set_type(req, "application/json");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  httpd_resp_sendstr(req, "{\"success\":true,\"message\":\"Arduino guncelleme tamamlandi.\"}");
  return ESP_OK;
}

// --- CORS OPTIONS handler ---
static esp_err_t optionsHandler(httpd_req_t *req) {
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Headers", "Content-Type");
  httpd_resp_send(req, NULL, 0);
  return ESP_OK;
}

// ===================== HTTP SUNUCU BAŞLATMA =====================

void startHTTPServer() {
  httpd_config_t config = HTTPD_DEFAULT_CONFIG();
  config.server_port = 80;
  config.max_uri_handlers = 20;  // [2] Artırıldı — yeni endpoint'ler için
  config.stack_size = 8192;

  if (httpd_start(&httpServer, &config) == ESP_OK) {
    httpd_uri_t statusUri = {"/api/status", HTTP_GET, statusHandler, NULL};
    httpd_register_uri_handler(httpServer, &statusUri);

    httpd_uri_t ardStatusUri = {"/api/arduino/status", HTTP_GET, arduinoStatusHandler, NULL};
    httpd_register_uri_handler(httpServer, &ardStatusUri);

    httpd_uri_t captureUri = {"/api/capture", HTTP_GET, captureHandler, NULL};
    httpd_register_uri_handler(httpServer, &captureUri);

    httpd_uri_t ardCmdUri = {"/api/arduino/command", HTTP_POST, arduinoCommandHandler, NULL};
    httpd_register_uri_handler(httpServer, &ardCmdUri);

    // [2] Kamera ayarları endpoint
    httpd_uri_t camSettingsUri = {"/api/camera/settings", HTTP_POST, cameraSettingsHandler, NULL};
    httpd_register_uri_handler(httpServer, &camSettingsUri);

    httpd_uri_t sdListUri = {"/api/sd/list", HTTP_GET, sdListHandler, NULL};
    httpd_register_uri_handler(httpServer, &sdListUri);

    httpd_uri_t sdPhotoUri = {"/api/sd/photo", HTTP_GET, sdPhotoHandler, NULL};
    httpd_register_uri_handler(httpServer, &sdPhotoUri);

    httpd_uri_t sdDeleteUri = {"/api/sd/photo", HTTP_DELETE, sdDeleteHandler, NULL};
    httpd_register_uri_handler(httpServer, &sdDeleteUri);

    httpd_uri_t otaEspUri = {"/api/ota/esp32", HTTP_POST, otaEsp32Handler, NULL};
    httpd_register_uri_handler(httpServer, &otaEspUri);

    httpd_uri_t otaArdUri = {"/api/ota/arduino", HTTP_POST, otaArduinoHandler, NULL};
    httpd_register_uri_handler(httpServer, &otaArdUri);

    // CORS preflight
    httpd_uri_t optArd = {"/api/arduino/command", HTTP_OPTIONS, optionsHandler, NULL};
    httpd_register_uri_handler(httpServer, &optArd);
    httpd_uri_t optCam = {"/api/camera/settings", HTTP_OPTIONS, optionsHandler, NULL};
    httpd_register_uri_handler(httpServer, &optCam);

    Serial.println("[HTTP] Sunucu baslatildi, port: 80");
  }

  // Stream sunucusu (ayrı port)
  httpd_config_t streamConfig = HTTPD_DEFAULT_CONFIG();
  streamConfig.server_port = 81;
  streamConfig.ctrl_port = 32769;

  if (httpd_start(&streamServer, &streamConfig) == ESP_OK) {
    httpd_uri_t streamUri = {"/api/stream", HTTP_GET, streamHandler, NULL};
    httpd_register_uri_handler(streamServer, &streamUri);
    Serial.println("[Stream] Sunucu baslatildi, port: 81");
  }
}

// ===================== SETUP =====================

void setup() {
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);

  Serial.begin(115200);
  delay(500);

  Serial.println();
  Serial.println("==========================================");
  Serial.println(" AntaresStudio IoT - ESP32-CAM v" FW_VERSION);
  Serial.println(" Production Ready");
  Serial.println("==========================================");

  // LED
  pinMode(LED_BUILTIN_PIN, OUTPUT);
  digitalWrite(LED_BUILTIN_PIN, HIGH);

  // Arduino RESET pin
  pinMode(ARDUINO_RESET_PIN, OUTPUT);
  digitalWrite(ARDUINO_RESET_PIN, HIGH);

  // [1] NVS ayarları yükle
  loadNVSSettings();

  // 1. UART2: Arduino ile haberleşme
  Serial2.begin(115200, SERIAL_8N1, UART_RX_PIN, UART_TX_PIN);
  Serial.printf("[UART] Acildi: 115200 baud, TX=%d, RX=%d\n", UART_TX_PIN, UART_RX_PIN);

  // 2. Kamera
  if (initCamera()) {
    Serial.println("[Camera] Hazir.");
  } else {
    Serial.println("[Camera] HATA!");
  }

  // 3. SD Kart
  if (SD_MMC.begin("/sdcard", true)) {
    uint64_t cardSize = SD_MMC.cardSize() / (1024 * 1024);
    Serial.printf("[SD] Kart hazir: %llu MB\n", cardSize);
    sdCardReady = true;
    sdErrorCount = 0;
  } else {
    Serial.println("[SD] SD kart bulunamadi veya hata! Otonom cekim devre disi.");
    sdCardReady = false;
  }

  // 4. Wi-Fi AP
  WiFi.mode(WIFI_AP);
  WiFi.softAP(AP_SSID, AP_PASSWORD);
  delay(500);
  Serial.printf("[WiFi] AP baslatildi: %s\n", AP_SSID);
  Serial.printf("[WiFi] IP: %s\n", WiFi.softAPIP().toString().c_str());

  // 5. HTTP Sunucusu
  startHTTPServer();

  // Hazır
  digitalWrite(LED_BUILTIN_PIN, LOW);
  Serial.println();
  Serial.println("[SISTEM] Tum servisler hazir!");
  Serial.printf("[SISTEM] AP: %s (sifre: %s)\n", AP_SSID, AP_PASSWORD);
  Serial.printf("[SISTEM] HTTP: http://%s\n", WiFi.softAPIP().toString().c_str());
  Serial.printf("[SISTEM] Stream: http://%s:81/api/stream\n", WiFi.softAPIP().toString().c_str());
  Serial.println();
}

// ===================== LOOP =====================

void loop() {
  // 1. Arduino tetiklerini dinle
  listenArduinoTriggers();

  // 2. Bridge modu timeout kontrolü
  if (bridgeModeActive) {
    if (millis() - bridgeLastActivity > BRIDGE_TIMEOUT_MS) {
      Serial.println("[Bridge] Zaman asimi! Kapatiliyor.");
      endBridge();
    }
  }

  // 3. [4] SD kart sağlık kontrolü (60 saniyede bir)
  static unsigned long lastSDCheck = 0;
  if (millis() - lastSDCheck > 60000) {
    lastSDCheck = millis();
    checkSDHealth();
  }

  // 4. Durum yazdırma (her 30 saniyede)
  static unsigned long lastPrint = 0;
  if (millis() - lastPrint > 30000) {
    lastPrint = millis();
    Serial.printf("[Durum] Heap: %u, PSRAM: %u, Clients: %d, SD: %s (err:%d), UART: %s\n",
      ESP.getFreeHeap(), ESP.getFreePsram(),
      WiFi.softAPgetStationNum(),
      sdCardReady ? "OK" : "YOK", sdErrorCount,
      uartBusy ? "MESGUL" : "HAZIR");
  }

  delay(10);
}
