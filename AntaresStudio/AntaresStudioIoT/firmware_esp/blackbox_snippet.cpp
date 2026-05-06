// ============================================================
// Antares ESP32-CAM v3.2 - Black Box (Kara Kutu) Recording System
// 
// Add these modifications to firmware_esp.ino for mission recording.
//
// Features:
//   [1] is_record flag in telemetry JSON
//   [2] 15-second SD card logging loop
//   [3] Stream upload to backend on STOP command
//   [4] Auto-cleanup after successful transfer
// ============================================================

#include <FS.h>
#include <SD_MMC.h>
#include <HTTPClient.h>

// ============================================================
// BLACK BOX CONFIGURATION
// ============================================================

#define BLACKBOX_FILENAME "/blackbox.txt"
#define BLACKBOX_INTERVAL_MS 15000  // 15 seconds

// Recording state
bool isRecording = false;
unsigned long lastRecordTime = 0;
File blackboxFile;

// Last telemetry values for logging
struct BlackBoxData {
  float temperature = 0.0;
  int humidity = 0;
  int soilMoisture = 0;
  int heaterPower = 0;
  bool fanSly = false;
  bool fanDz = false;
  String mode = "STANDBY";
  unsigned long timestamp = 0;
} lastTelemetry;

// ============================================================
// BLACK BOX FILE OPERATIONS
// ============================================================

/**
 * Initialize black box system
 * Checks if previous recording exists (crash recovery)
 */
void initBlackBox() {
  if (!sdMounted) {
    logSD("WARNING", "Black Box: SD not mounted, recording disabled");
    return;
  }
  
  // Check for orphaned recording file
  if (SD_MMC.exists(BLACKBOX_FILENAME)) {
    File f = SD_MMC.open(BLACKBOX_FILENAME, FILE_READ);
    if (f) {
      size_t size = f.size();
      f.close();
      
      if (size > 0) {
        logSD("WARNING", ("Black Box: Found orphaned recording (" + String(size) + " bytes)").c_str());
        logSD("INFO", "Black Box: Previous recording will be uploaded on next STOP command");
      }
    }
  }
  
  logSD("INFO", "Black Box system initialized");
}

/**
 * Start recording session
 * Creates/opens blackbox.txt and writes header
 */
bool startRecording() {
  if (!sdMounted) {
    logSD("ERROR", "Black Box: Cannot start - SD not mounted");
    return false;
  }
  
  if (isRecording) {
    logSD("WARNING", "Black Box: Already recording");
    return false;
  }
  
  // Delete old file if exists
  if (SD_MMC.exists(BLACKBOX_FILENAME)) {
    SD_MMC.remove(BLACKBOX_FILENAME);
  }
  
  // Create new file with header
  blackboxFile = SD_MMC.open(BLACKBOX_FILENAME, FILE_WRITE);
  if (!blackboxFile) {
    logSD("ERROR", "Black Box: Failed to create file");
    return false;
  }
  
  // Write CSV header
  blackboxFile.println("timestamp,datetime,temperature,humidity,soil_moisture,heater_power,fan_sly,fan_dz,mode");
  blackboxFile.flush();
  
  isRecording = true;
  lastRecordTime = millis();
  
  // Log mission start
  String startMsg = "MISSION_START," + String(millis());
  logSD("BLACKBOX", "=== RECORDING STARTED ===");
  
  return true;
}

/**
 * Stop recording session
 * Closes file and triggers upload
 */
bool stopRecording() {
  if (!isRecording) {
    logSD("WARNING", "Black Box: Not currently recording");
    return false;
  }
  
  isRecording = false;
  
  if (blackboxFile) {
    // Write mission end marker
    blackboxFile.print("MISSION_END,");
    blackboxFile.println(millis());
    blackboxFile.flush();
    blackboxFile.close();
  }
  
  logSD("BLACKBOX", "=== RECORDING STOPPED ===");
  
  // Trigger upload to backend
  return uploadBlackBoxToBackend();
}

/**
 * Append telemetry to black box file
 * Called every 15 seconds when recording
 */
void appendToBlackBox(const BlackBoxData& data) {
  if (!isRecording || !blackboxFile) return;
  
  // Format: timestamp,datetime,temperature,humidity,soil_moisture,heater_power,fan_sly,fan_dz,mode
  char line[256];
  snprintf(line, sizeof(line), "%lu,%s,%.2f,%d,%d,%d,%s,%s,%s",
    data.timestamp,
    formatDateTime(data.timestamp).c_str(),
    data.temperature,
    data.humidity,
    data.soilMoisture,
    data.heaterPower,
    data.fanSly ? "ON" : "OFF",
    data.fanDz ? "ON" : "OFF",
    data.mode.c_str()
  );
  
  blackboxFile.println(line);
  blackboxFile.flush();
  
  logSD("BLACKBOX", ("Logged: " + String(data.temperature) + "°C, " + String(data.humidity) + "% RH").c_str());
}

/**
 * Helper: Format timestamp to human-readable datetime
 */
String formatDateTime(unsigned long timestamp) {
  // Convert millis() to approximate datetime string
  // For accurate time, you'd need NTP sync
  unsigned long seconds = timestamp / 1000;
  int hours = (seconds / 3600) % 24;
  int minutes = (seconds / 60) % 60;
  int secs = seconds % 60;
  
  char buf[32];
  snprintf(buf, sizeof(buf), "T+%02d:%02d:%02d", hours, minutes, secs);
  return String(buf);
}

// ============================================================
// UPLOAD TO BACKEND
// ============================================================

/**
 * Upload blackbox.txt to backend endpoint
 * Stream in chunks to handle large files
 * Delete local file only after successful confirmation
 */
bool uploadBlackBoxToBackend() {
  if (!sdMounted) {
    logSD("ERROR", "Black Box: Cannot upload - SD not mounted");
    return false;
  }
  
  if (!SD_MMC.exists(BLACKBOX_FILENAME)) {
    logSD("WARNING", "Black Box: No file to upload");
    return false;
  }
  
  File uploadFile = SD_MMC.open(BLACKBOX_FILENAME, FILE_READ);
  if (!uploadFile) {
    logSD("ERROR", "Black Box: Failed to open file for upload");
    return false;
  }
  
  size_t fileSize = uploadFile.size();
  logSD("INFO", ("Black Box: Uploading " + String(fileSize) + " bytes to backend...").c_str());
  
  // Build upload URL
  String url = "http://" + PC_BACKEND_IP + ":" + String(PC_BACKEND_PORT) + "/api/v1/blackbox/upload";
  
  HTTPClient http;
  http.setTimeout(60000);  // 60 second timeout for large files
  http.begin(url);
  
  // Headers
  http.addHeader("Content-Type", "text/plain");
  http.addHeader("X-ESP32-CAM", "true");
  http.addHeader("X-File-Size", String(fileSize));
  
  // Read file and POST
  // For large files, read in chunks
  const size_t chunkSize = 4096;
  uint8_t* buffer = (uint8_t*)malloc(chunkSize);
  
  if (!buffer) {
    logSD("ERROR", "Black Box: Failed to allocate upload buffer");
    uploadFile.close();
    return false;
  }
  
  // Simple approach: read entire file to String (for files < 100KB)
  // For larger files, use chunked approach
  String payload = "";
  payload.reserve(fileSize + 1);
  
  while (uploadFile.available()) {
    payload += (char)uploadFile.read();
    
    // Feed watchdog during large reads
    if (payload.length() % 1024 == 0) {
      esp_task_wdt_reset();
      yield();
    }
  }
  
  uploadFile.close();
  
  logSD("INFO", ("Black Box: POSTing " + String(payload.length()) + " bytes...").c_str());
  
  int httpCode = http.POST(payload);
  payload.clear();  // Free memory
  free(buffer);
  
  bool success = false;
  
  if (httpCode == 200) {
    String response = http.getString();
    logSD("INFO", ("Black Box: Server response: " + response).c_str());
    
    // Parse response
    StaticJsonDocument<256> doc;
    DeserializationError error = deserializeJson(doc, response);
    
    if (!error && doc["success"] == true) {
      success = true;
      String pdfPath = doc["pdf_path"] | "unknown";
      logSD("SUCCESS", ("Black Box: Upload OK, PDF: " + pdfPath).c_str());
      
      // Delete local file after successful upload
      if (SD_MMC.remove(BLACKBOX_FILENAME)) {
        logSD("INFO", "Black Box: Local file deleted after successful upload");
      } else {
        logSD("WARNING", "Black Box: Failed to delete local file");
      }
    } else {
      logSD("ERROR", "Black Box: Server rejected upload");
    }
  } else if (httpCode > 0) {
    logSD("ERROR", ("Black Box: HTTP error " + String(httpCode)).c_str());
  } else {
    logSD("ERROR", ("Black Box: Connection failed: " + String(http.errorToString(httpCode).c_str())).c_str());
  }
  
  http.end();
  return success;
}

// ============================================================
// RECORDING LOOP - Call from main loop()
// ============================================================

/**
 * Call this from your main loop() every iteration
 * Handles 15-second recording interval
 */
void handleBlackBoxLoop() {
  if (!isRecording) return;
  
  unsigned long now = millis();
  if (now - lastRecordTime >= BLACKBOX_INTERVAL_MS) {
    lastRecordTime = now;
    
    // Update timestamp
    lastTelemetry.timestamp = now;
    
    // Append to file
    appendToBlackBox(lastTelemetry);
  }
}

// ============================================================
// TELEMETRY UPDATE - Call when new data arrives from Arduino
// ============================================================

/**
 * Update telemetry data for black box recording
 * Call this when you parse CSV from Arduino
 */
void updateBlackBoxTelemetry(const String& csvLine) {
  // Parse: DATA,temp,hum,soil,mode,heater,fanSly,fanDz,motorPos,isHomed
  if (!csvLine.startsWith("DATA,")) return;
  
  int parts[10];
  int partIndex = 0;
  int start = 5;  // Skip "DATA,"
  
  // Simple CSV parsing
  String value = "";
  for (int i = start; i <= csvLine.length(); i++) {
    char c = (i < csvLine.length()) ? csvLine[i] : ',';
    
    if (c == ',' || i == csvLine.length()) {
      // Parse value based on position
      switch (partIndex) {
        case 0: lastTelemetry.temperature = value.toFloat(); break;
        case 1: lastTelemetry.humidity = value.toInt(); break;
        case 2: lastTelemetry.soilMoisture = value.toInt(); break;
        case 3: lastTelemetry.mode = value; break;
        case 4: lastTelemetry.heaterPower = value.toInt(); break;
        case 5: lastTelemetry.fanSly = (value == "true" || value == "1"); break;
        case 6: lastTelemetry.fanDz = (value == "true" || value == "1"); break;
      }
      value = "";
      partIndex++;
    } else {
      value += c;
    }
  }
}

// ============================================================
// HTTP ENDPOINTS - Add to your server setup
// ============================================================

void setupBlackBoxEndpoints() {
  // GET /api/blackbox/status - Check recording status
  server.on("/api/blackbox/status", HTTP_GET, [](AsyncWebServerRequest *request) {
    StaticJsonDocument<256> doc;
    doc["is_recording"] = isRecording;
    doc["last_record_time"] = lastRecordTime;
    doc["file_exists"] = SD_MMC.exists(BLACKBOX_FILENAME);
    
    if (SD_MMC.exists(BLACKBOX_FILENAME)) {
      File f = SD_MMC.open(BLACKBOX_FILENAME, FILE_READ);
      if (f) {
        doc["file_size"] = f.size();
        f.close();
      }
    }
    
    String response;
    serializeJson(doc, response);
    
    AsyncWebServerResponse *resp = request->beginResponse(200, "application/json", response);
    resp->addHeader("Access-Control-Allow-Origin", "*");
    request->send(resp);
  });
  
  // POST /api/blackbox/start - Start recording
  server.on("/api/blackbox/start", HTTP_POST, [](AsyncWebServerRequest *request) {
    bool started = startRecording();
    
    StaticJsonDocument<128> doc;
    doc["success"] = started;
    doc["message"] = started ? "Recording started" : "Failed to start recording";
    doc["is_recording"] = isRecording;
    
    String response;
    serializeJson(doc, response);
    
    AsyncWebServerResponse *resp = request->beginResponse(
      started ? 200 : 500, "application/json", response);
    resp->addHeader("Access-Control-Allow-Origin", "*");
    request->send(resp);
  });
  
  // POST /api/blackbox/stop - Stop recording and upload
  server.on("/api/blackbox/stop", HTTP_POST, [](AsyncWebServerRequest *request) {
    bool stopped = stopRecording();
    
    StaticJsonDocument<256> doc;
    doc["success"] = stopped;
    doc["message"] = stopped ? "Recording stopped and uploaded" : "Failed to stop/upload";
    doc["is_recording"] = isRecording;
    doc["file_deleted"] = !SD_MMC.exists(BLACKBOX_FILENAME);
    
    String response;
    serializeJson(doc, response);
    
    AsyncWebServerResponse *resp = request->beginResponse(
      stopped ? 200 : 500, "application/json", response);
    resp->addHeader("Access-Control-Allow-Origin", "*");
    request->send(resp);
  });
  
  // CORS preflight
  server.on("/api/blackbox/start", HTTP_OPTIONS, [](AsyncWebServerRequest *request) {
    AsyncWebServerResponse *response = request->beginResponse(200);
    response->addHeader("Access-Control-Allow-Origin", "*");
    response->addHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
    response->addHeader("Access-Control-Allow-Headers", "Content-Type");
    request->send(response);
  });
  
  server.on("/api/blackbox/stop", HTTP_OPTIONS, [](AsyncWebServerRequest *request) {
    AsyncWebServerResponse *response = request->beginResponse(200);
    response->addHeader("Access-Control-Allow-Origin", "*");
    response->addHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
    response->addHeader("Access-Control-Allow-Headers", "Content-Type");
    request->send(response);
  });
  
  logSD("INFO", "Black Box endpoints ready");
}

// ============================================================
// TELEMETRY JSON MODIFICATION
// Add is_record field to existing telemetry JSON
// ============================================================

/**
 * When building telemetry JSON for /api/status or WebSocket,
 * add the is_record field:
 * 
 * Example output:
 * {
 *   "temperature": 25.5,
 *   "humidity": 60,
 *   "soil_moisture": 512,
 *   "mode": "AUTO",
 *   "is_record": true,    <-- ADD THIS
 *   "timestamp": 12345678
 * }
 */
String buildTelemetryJson() {
  StaticJsonDocument<512> doc;
  
  doc["temperature"] = lastTelemetry.temperature;
  doc["humidity"] = lastTelemetry.humidity;
  doc["soil_moisture"] = lastTelemetry.soilMoisture;
  doc["heater_power"] = lastTelemetry.heaterPower;
  doc["fan_sly"] = lastTelemetry.fanSly;
  doc["fan_dz"] = lastTelemetry.fanDz;
  doc["mode"] = lastTelemetry.mode;
  doc["motor_position"] = 0;  // From your existing code
  doc["is_homed"] = false;    // From your existing code
  doc["is_record"] = isRecording;  // <-- BLACK BOX FLAG
  doc["timestamp"] = millis();
  
  String output;
  serializeJson(doc, output);
  return output;
}
