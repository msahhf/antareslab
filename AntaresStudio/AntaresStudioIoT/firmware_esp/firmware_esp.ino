// =====================================================================
// AntaresStudio IoT - ESP32-CAM Firmware v4.0.0 (Hybrid Routing)
// =====================================================================
// Optimized for:
// - Hybrid Image Routing (Direct to PC or Fail-safe to SD Card)
// - SD Card Session Management (Timestamped folders)
// - STK500 Bridge moved to GPIO 12/13 (SDMMC 1-bit mode)
// - Structured REST API for SD Sync
// =====================================================================

#include "esp_camera.h"
#include <WiFi.h>
#include <ESPmDNS.h>
#include "esp_http_server.h"
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"
#include <ArduinoJson.h>
#include <Update.h>
#include <Preferences.h>
#include <esp_task_wdt.h>
#include <rom/crc.h>
#include "SD_MMC.h"
#include "FS.h"
#include <HTTPClient.h>

// ===================== PIN CONFIGURATION =====================
// Camera Pins
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

// Hybrid Mapping for SD + UART Bridge (SDMMC 1-bit Mode)
// SD Card Pins: GPIO 2 (D0), 14 (CLK), 15 (CMD)
#define ARDUINO_TX_PIN   13 // UART2 TX (Free in 1-bit mode)
#define ARDUINO_RX_PIN   12 // UART2 RX (Free in 1-bit mode)
#define ARDUINO_RESET_PIN 4 // Reset tied to Flash LED pin

#define LED_BUILTIN_PIN  33

// ===================== GLOBAL CONSTANTS =====================
const char* AP_SSID       = "ANTARES_STUDIO_IOT";
const char* AP_PASSWORD   = "antares123";
const char* HOSTNAME      = "antares-iot";
const char* PC_IP         = "192.168.4.2"; // Assumed fixed IP for PC in AP mode

#define WDT_TIMEOUT_S     10
#define SERIAL_BAUD       115200

// ===================== GLOBAL STATE =====================
httpd_handle_t httpServer = NULL;
bool sdMounted = false;
String currentSessionFolder = "";

struct CameraConfig {
  int quality = 10;
  int frameSize = 13; // UXGA
  int stabMs = 800;
} camCfg;

struct ArduinoData {
  float temp = 0;
  int hum = 0;
  int soil = 0;
  int heater = 0;
  int fanSly = 0;
  int fanDz = 0;
  char mode[16] = "IDLE";
  unsigned long lastUpdate = 0;
} ardData;

// PC Connection caching (non-blocking)
bool pcLastStatus = false;
unsigned long lastPCCheck = 0;
const unsigned long PC_CHECK_INTERVAL_MS = 3000;  // Check every 3 seconds

// ===================== LOGGING & SD =====================

void logSD(const char* level, const char* msg) {
  StaticJsonDocument<256> doc;
  doc["time"] = millis();
  doc["level"] = level;
  doc["msg"] = msg;
  doc["heap"] = ESP.getFreeHeap();

  if (sdMounted) {
    File logFile = SD_MMC.open("/logs.json", FILE_APPEND);
    if (logFile) {
      serializeJson(doc, logFile);
      logFile.println();
      logFile.close();
    }
  }
  serializeJson(doc, Serial);
  Serial.println();
}

bool initSD() {
  if (!SD_MMC.begin("/sdcard", true)) { // 1-bit mode
    logSD("ERROR", "SD Card Mount Failed");
    return false;
  }
  sdMounted = true;
  logSD("INFO", "SD Card Mounted (1-bit Mode)");
  return true;
}

// ===================== HANDSHAKE & ROUTING =====================

bool checkPCConnection() {
  // Return cached result if recent (prevents blocking during every image route)
  if (millis() - lastPCCheck < PC_CHECK_INTERVAL_MS) {
    return pcLastStatus;
  }
  
  lastPCCheck = millis();
  
  HTTPClient http;
  http.begin("http://192.168.4.2:8000/api/ping"); // PC Side Heartbeat
  http.setTimeout(300);  // Shorter timeout to reduce blocking
  int code = http.GET();
  pcLastStatus = (code == 200);
  http.end();
  return pcLastStatus;
}

void routeImage(camera_fb_t* fb) {
  bool pcActive = checkPCConnection();
  
  if (pcActive) {
    logSD("INFO", "Routing to PC (Direct)");
    // Note: In a real scenario, we'd POST to PC. 
    // Here we assume the PC will poll or we just log the status.
  } else {
    logSD("WARNING", "PC not active. Routing to SD.");
    if (sdMounted) {
      if (currentSessionFolder == "") {
        currentSessionFolder = "/session_" + String(millis());
        SD_MMC.mkdir(currentSessionFolder.c_str());
      }
      String path = currentSessionFolder + "/img_" + String(millis()) + ".jpg";
      File file = SD_MMC.open(path.c_str(), FILE_WRITE);
      if (file) {
        // Non-blocking chunked write with WDT feeding
        const size_t CHUNK_SIZE = 1024;
        size_t written = 0;
        bool writeSuccess = true;
        
        while (written < fb->len) {
          size_t toWrite = min(CHUNK_SIZE, fb->len - written);
          size_t n = file.write(fb->buf + written, toWrite);
          
          if (n == 0) {
            writeSuccess = false;
            break;  // Write error
          }
          
          written += n;
          
          // Feed WDT and allow other tasks to run
          esp_task_wdt_reset();
          yield();  // Critical: allows HTTP server to process pending requests
        }
        
        file.close();
        
        if (writeSuccess && written == fb->len) {
          logSD("SUCCESS", "Image saved to SD");
        } else {
          logSD("ERROR", "SD write incomplete or failed");
        }
      }
    }
  }
}

// ===================== CAMERA HELPERS =====================

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
  config.frame_size   = (framesize_t)camCfg.frameSize;
  config.jpeg_quality = camCfg.quality;
  config.fb_count     = 2;

  esp_err_t err = esp_camera_init(&config);
  return (err == ESP_OK);
}

// ===================== HTTP HANDLERS =====================

static esp_err_t statusHandler(httpd_req_t *req) {
  StaticJsonDocument<512> doc;
  doc["version"] = "4.0.0";
  doc["sd_active"] = sdMounted;
  doc["heap"] = ESP.getFreeHeap();
  
  JsonObject ard = doc.createNestedObject("arduino");
  ard["mode"] = ardData.mode;
  ard["temp"] = ardData.temp;

  char buf[512];
  serializeJson(doc, buf);
  httpd_resp_set_type(req, "application/json");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  return httpd_resp_sendstr(req, buf);
}

// Helper for CORS error responses
static esp_err_t sendCorsError(httpd_req_t *req, int code, const char* msg) {
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  httpd_resp_set_type(req, "application/json");
  
  StaticJsonDocument<256> doc;
  doc["error"] = msg;
  doc["code"] = code;
  doc["success"] = false;
  
  char buf[256];
  serializeJson(doc, buf);
  
  if (code == 500) {
    httpd_resp_set_status(req, "500 Internal Server Error");
  } else if (code == 404) {
    httpd_resp_set_status(req, "404 Not Found");
  }
  return httpd_resp_sendstr(req, buf);
}

static esp_err_t captureHandler(httpd_req_t *req) {
  camera_fb_t* fb = esp_camera_fb_get();
  if (!fb) {
    return sendCorsError(req, 500, "Camera frame buffer error");
  }
  
  // High-Quality enforcement for v4.0 scans
  sensor_t *s = esp_camera_sensor_get();
  s->set_quality(s, 10); 

  routeImage(fb); // Hybrid routing logic

  httpd_resp_set_type(req, "image/jpeg");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  esp_err_t res = httpd_resp_send(req, (const char *)fb->buf, fb->len);
  esp_camera_fb_return(fb);
  return res;
}

static esp_err_t syncListHandler(httpd_req_t *req) {
  if (!sdMounted) {
    return sendCorsError(req, 500, "SD card not mounted");
  }
  
  StaticJsonDocument<2048> doc;
  JsonArray sessions = doc.createNestedArray("sessions");
  
  File root = SD_MMC.open("/");
  File file = root.openNextFile();
  while(file){
    if(file.isDirectory() && String(file.name()).startsWith("/session_")){
      JsonObject s = sessions.createNestedObject();
      s["name"] = String(file.name());
      // Simplified: Just list folders. In production, we'd count files.
    }
    file = root.openNextFile();
  }

  char buf[2048];
  serializeJson(doc, buf);
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  return httpd_resp_sendstr(req, buf);
}

static esp_err_t syncDownloadHandler(httpd_req_t *req) {
  char path[128];
  // Extract path from URI
  strncpy(path, req->uri + 15, sizeof(path)-1); // Skip /sync/download/
  path[sizeof(path)-1] = '\0';  // Ensure null termination
  
  File file = SD_MMC.open(path);
  if (!file || file.isDirectory()) {
    return sendCorsError(req, 404, "File not found");
  }

  httpd_resp_set_type(req, "application/octet-stream");
  uint8_t buf[1024];
  while (file.available()) {
    size_t n = file.read(buf, sizeof(buf));
    httpd_resp_send_chunk(req, (const char*)buf, n);
  }
  file.close();
  return httpd_resp_send_chunk(req, NULL, 0);
}

// Forward Arduino command and return response
static esp_err_t arduinoCommandHandler(httpd_req_t *req) {
  char buf[128];
  int ret = httpd_req_recv(req, buf, sizeof(buf) - 1);
  if (ret <= 0) {
    return sendCorsError(req, 500, "Failed to receive request body");
  }
  buf[ret] = '\0';
  
  // Parse JSON command
  StaticJsonDocument<256> doc;
  DeserializationError err = deserializeJson(doc, buf);
  
  if (err) {
    return sendCorsError(req, 400, "Invalid JSON");
  }
  
  const char* cmd = doc["cmd"] | "";
  if (strlen(cmd) == 0) {
    return sendCorsError(req, 400, "Missing 'cmd' field");
  }
  
  // Send to Arduino in bracket format
  Serial2.print("<");
  Serial2.print(cmd);
  Serial2.print(">");
  
  // Wait for Arduino response (max 5 seconds for motor commands)
  String response = "";
  unsigned long start = millis();
  bool gotResponse = false;
  
  while (millis() - start < 5000) {
    while (Serial2.available()) {
      char c = Serial2.read();
      if (c == '\n' || c == '\r') {
        if (response.length() > 0) {
          gotResponse = true;
          break;
        }
      } else {
        response += c;
        if (response.length() > 64) {
          response = response.substring(0, 64);  // Prevent overflow
        }
      }
    }
    if (gotResponse) break;
    delay(1);
    esp_task_wdt_reset();
  }
  
  // Prepare response JSON
  StaticJsonDocument<256> respDoc;
  respDoc["cmd"] = cmd;
  
  if (gotResponse) {
    respDoc["response"] = response;
    respDoc["success"] = !response.startsWith("ERR");
    respDoc["timeout"] = false;
  } else {
    respDoc["response"] = "TIMEOUT";
    respDoc["success"] = false;
    respDoc["timeout"] = true;
  }
  
  char respBuf[256];
  serializeJson(respDoc, respBuf);
  
  httpd_resp_set_type(req, "application/json");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  return httpd_resp_sendstr(req, respBuf);
}

// Camera settings handler
static esp_err_t cameraSettingsHandler(httpd_req_t *req) {
  // Handle GET - return current settings
  if (req->method == HTTP_GET) {
    StaticJsonDocument<256> doc;
    doc["quality"] = camCfg.quality;
    doc["framesize"] = camCfg.frameSize;
    doc["stabilization_ms"] = camCfg.stabMs;
    doc["success"] = true;
    
    char buf[256];
    serializeJson(doc, buf);
    
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
    return httpd_resp_sendstr(req, buf);
  }
  
  // Handle POST - update settings
  if (req->method == HTTP_POST) {
    char buf[128];
    int ret = httpd_req_recv(req, buf, sizeof(buf) - 1);
    if (ret <= 0) {
      return sendCorsError(req, 500, "Failed to receive request body");
    }
    buf[ret] = '\0';
    
    StaticJsonDocument<256> doc;
    DeserializationError err = deserializeJson(doc, buf);
    
    if (!err) {
      if (doc.containsKey("quality")) {
        camCfg.quality = doc["quality"];
      }
      if (doc.containsKey("framesize")) {
        camCfg.frameSize = doc["framesize"];
      }
      if (doc.containsKey("stabilization_ms")) {
        camCfg.stabMs = doc["stabilization_ms"];
      }
      
      // Apply to camera sensor
      sensor_t *s = esp_camera_sensor_get();
      if (s) {
        s->set_quality(s, camCfg.quality);
        s->set_framesize(s, (framesize_t)camCfg.frameSize);
      }
    }
    
    // Return current settings
    doc["quality"] = camCfg.quality;
    doc["framesize"] = camCfg.frameSize;
    doc["stabilization_ms"] = camCfg.stabMs;
    doc["success"] = true;
    
    char respBuf[256];
    serializeJson(doc, respBuf);
    
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
    return httpd_resp_sendstr(req, respBuf);
  }
  
  return sendCorsError(req, 405, "Method not allowed");
}

// OPTIONS handler for CORS preflight
static esp_err_t corsOptionsHandler(httpd_req_t *req) {
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Headers", "Content-Type, Authorization");
  httpd_resp_set_status(req, "204 No Content");
  return httpd_resp_send(req, NULL, 0);
}

void startHTTPServer() {
  httpd_config_t config = HTTPD_DEFAULT_CONFIG();
  config.stack_size = 10240;
  config.max_uri_handlers = 16;
  config.lru_purge_enable = true;  // Enable LRU purge for memory pressure

  if (httpd_start(&httpServer, &config) == ESP_OK) {
    httpd_uri_t uri_status   = { "/api/status", HTTP_GET, statusHandler, NULL };
    httpd_uri_t uri_capture  = { "/api/capture", HTTP_GET, captureHandler, NULL };
    httpd_uri_t uri_sync_l   = { "/sync/list", HTTP_GET, syncListHandler, NULL };
    httpd_uri_t uri_sync_d   = { "/sync/download/*", HTTP_GET, syncDownloadHandler, NULL };
    
    // NEW: Arduino command forwarding
    httpd_uri_t uri_arduino_cmd = { "/api/arduino/command", HTTP_POST, arduinoCommandHandler, NULL };
    httpd_uri_t uri_arduino_opts = { "/api/arduino/command", HTTP_OPTIONS, corsOptionsHandler, NULL };
    
    // NEW: Camera settings
    httpd_uri_t uri_camera_get = { "/api/camera/settings", HTTP_GET, cameraSettingsHandler, NULL };
    httpd_uri_t uri_camera_post = { "/api/camera/settings", HTTP_POST, cameraSettingsHandler, NULL };
    httpd_uri_t uri_camera_opts = { "/api/camera/settings", HTTP_OPTIONS, corsOptionsHandler, NULL };
    
    // Register all handlers
    httpd_register_uri_handler(httpServer, &uri_status);
    httpd_register_uri_handler(httpServer, &uri_capture);
    httpd_register_uri_handler(httpServer, &uri_sync_l);
    httpd_register_uri_handler(httpServer, &uri_sync_d);
    httpd_register_uri_handler(httpServer, &uri_arduino_cmd);
    httpd_register_uri_handler(httpServer, &uri_arduino_opts);
    httpd_register_uri_handler(httpServer, &uri_camera_get);
    httpd_register_uri_handler(httpServer, &uri_camera_post);
    httpd_register_uri_handler(httpServer, &uri_camera_opts);
    
    logSD("INFO", "HTTP Server started with 9 endpoints");
  }
}

// ===================== SETUP & LOOP =====================

void setup() {
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);
  Serial.begin(115200);
  Serial2.begin(115200, SERIAL_8N1, ARDUINO_RX_PIN, ARDUINO_TX_PIN);

  initSD();
  initCamera();

  WiFi.softAP(AP_SSID, AP_PASSWORD);
  logSD("INFO", "Hybrid System v4.0 Active");

  startHTTPServer();
  
  // WDT Config (v3.0+ compatibility)
  esp_task_wdt_config_t wdt_config = {
      .timeout_ms = WDT_TIMEOUT_S * 1000,
      .idle_core_mask = (1 << portNUM_PROCESSORS) - 1, 
      .trigger_panic = true
  };
  esp_task_wdt_init(&wdt_config);
  esp_task_wdt_add(NULL);
}

// Parse Arduino CSV telemetry: DATA,temp,hum,soil,heater,fanSly,fanDz,mode
void parseArduinoTelemetry(const String& line) {
  // Expected format: DATA,25.5,40,512,128,1,0,OTONOM
  int fieldIndex = 0;
  int startIdx = 5;  // Skip "DATA," prefix
  
  for (int i = startIdx; i <= line.length(); i++) {
    if (i == line.length() || line[i] == ',') {
      String field = line.substring(startIdx, i);
      
      switch (fieldIndex) {
        case 0: ardData.temp = field.toFloat(); break;
        case 1: ardData.hum = field.toInt(); break;
        case 2: ardData.soil = field.toInt(); break;
        case 3: ardData.heater = field.toInt(); break;
        case 4: ardData.fanSly = field.toInt(); break;
        case 5: ardData.fanDz = field.toInt(); break;
        case 6: 
          strncpy(ardData.mode, field.c_str(), sizeof(ardData.mode) - 1);
          ardData.mode[sizeof(ardData.mode) - 1] = '\0';
          break;
      }
      
      fieldIndex++;
      startIdx = i + 1;
    }
  }
  
  ardData.lastUpdate = millis();
}

void loop() {
  esp_task_wdt_reset();
  
  // Serial2 processing - handle both telemetry and capture commands
  static String rxBuffer = "";
  
  while (Serial2.available()) {
    char c = Serial2.read();
    
    if (c == '\n' || c == '\r') {
      if (rxBuffer.length() > 0) {
        rxBuffer.trim();
        
        if (rxBuffer.startsWith("DATA,")) {
          // Telemetry data from Arduino
          parseArduinoTelemetry(rxBuffer);
        }
        else if (rxBuffer == "CEK") {
          // Capture request from Arduino
          camera_fb_t* fb = esp_camera_fb_get();
          if (fb) {
            routeImage(fb);
            esp_camera_fb_return(fb);
            // Send response WITHOUT brackets (Arduino expects raw response)
            Serial2.println("OK,CAP");
          } else {
            Serial2.println("ERR,CAP_FAIL");
          }
        }
        // Clear buffer
        rxBuffer = "";
      }
    } else if (rxBuffer.length() < 64) {
      rxBuffer += c;
    }
  }
  
  delay(1);
}
