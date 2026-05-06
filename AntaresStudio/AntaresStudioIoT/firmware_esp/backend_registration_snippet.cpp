// ============================================================
// Antares ESP32-CAM v3.1 - Backend Auto-Discovery
// 
// Add these modifications to firmware_esp.ino for zero-config
// backend IP registration.
//
// This allows the PC backend to auto-register its IP with ESP32
// on startup, eliminating hardcoded IP addresses.
// ============================================================

#include <HTTPClient.h>
#include <ArduinoJson.h>

// ============================================================
// DYNAMIC BACKEND IP CONFIGURATION
// ============================================================

// Mutable backend IP (was: const char* PC_BACKEND_IP = "192.168.4.2")
String PC_BACKEND_IP = "192.168.4.2";  // Default fallback
int PC_BACKEND_PORT = 8000;
bool backendRegistered = false;
unsigned long lastBackendCheck = 0;

// ============================================================
// NEW HTTP ENDPOINT: /api/config/backend-ip
// ============================================================

/**
 * Handle POST /api/config/backend-ip
 * 
 * Request body (JSON):
 *   {
 *     "ip": "192.168.4.2",
 *     "port": 8000,
 *     "hostname": "ANTARES-PC"
 *   }
 * 
 * Or the ESP32 can use the sender's IP automatically if no body provided.
 */
void handleBackendConfig(AsyncWebServerRequest *request, uint8_t *data, size_t len, size_t index, size_t total) {
  logSD("INFO", "Received backend config request");
  
  String body = "";
  for (size_t i = 0; i < len; i++) {
    body += (char)data[i];
  }
  
  // Parse sender IP automatically
  String senderIP = request->client()->remoteIP().toString();
  logSD("INFO", ("Request from: " + senderIP).c_str());
  
  // Try to parse JSON body
  StaticJsonDocument<256> doc;
  DeserializationError error = deserializeJson(doc, body);
  
  if (!error) {
    // Use provided IP from JSON
    const char* providedIP = doc["ip"];
    int providedPort = doc["port"] | 8000;
    const char* hostname = doc["hostname"] | "unknown";
    
    if (providedIP && strlen(providedIP) > 0) {
      PC_BACKEND_IP = String(providedIP);
      PC_BACKEND_PORT = providedPort;
      backendRegistered = true;
      
      String logMsg = "Backend registered: " + PC_BACKEND_IP + ":" + String(PC_BACKEND_PORT);
      if (hostname) {
        logMsg += " (" + String(hostname) + ")";
      }
      logSD("SUCCESS", logMsg.c_str());
      
      // Respond with success
      AsyncWebServerResponse *response = request->beginResponse(200, "application/json", 
        "{\"ok\": true, \"message\": \"Backend IP registered\", \"stored_ip\": \"" + PC_BACKEND_IP + "\"}");
      response->addHeader("Access-Control-Allow-Origin", "*");
      request->send(response);
      return;
    }
  }
  
  // Fallback: use sender's IP if no valid JSON body
  if (senderIP.length() > 0 && senderIP != "0.0.0.0") {
    PC_BACKEND_IP = senderIP;
    backendRegistered = true;
    
    String logMsg = "Backend auto-registered from sender IP: " + PC_BACKEND_IP;
    logSD("SUCCESS", logMsg.c_str());
    
    AsyncWebServerResponse *response = request->beginResponse(200, "application/json",
      "{\"ok\": true, \"message\": \"Backend IP auto-registered from sender\", \"stored_ip\": \"" + PC_BACKEND_IP + "\"}");
    response->addHeader("Access-Control-Allow-Origin", "*");
    request->send(response);
    return;
  }
  
  // Failed
  logSD("ERROR", "Could not determine backend IP from request");
  AsyncWebServerResponse *response = request->beginResponse(400, "application/json",
    "{\"ok\": false, \"error\": \"Could not determine backend IP\"}");
  response->addHeader("Access-Control-Allow-Origin", "*");
  request->send(response);
}

/**
 * Handle GET /api/config/backend-ip
 * Returns currently registered backend IP
 */
void handleGetBackendConfig(AsyncWebServerRequest *request) {
  StaticJsonDocument<256> doc;
  doc["ip"] = PC_BACKEND_IP;
  doc["port"] = PC_BACKEND_PORT;
  doc["registered"] = backendRegistered;
  doc["last_check"] = lastBackendCheck;
  
  String response;
  serializeJson(doc, response);
  
  AsyncWebServerResponse *resp = request->beginResponse(200, "application/json", response);
  resp->addHeader("Access-Control-Allow-Origin", "*");
  request->send(resp);
}

// ============================================================
// UPDATED: uploadToBackendDirect() uses dynamic PC_BACKEND_IP
// ============================================================

bool uploadToBackendDirect(camera_fb_t* fb, int photoIndex) {
  if (!fb || !fb->buf || fb->len == 0) {
    logSD("ERROR", "Invalid framebuffer for upload");
    return false;
  }
  
  // Check if we have a registered backend
  if (!backendRegistered && PC_BACKEND_IP == "192.168.4.2") {
    logSD("WARNING", "Backend IP not registered, using default 192.168.4.2");
  }
  
  HTTPClient http;
  String url = "http://" + PC_BACKEND_IP + ":" + String(PC_BACKEND_PORT) + 
               "/api/v1/photos/esp32-direct?index=" + String(photoIndex);
  
  // Add session_id if available
  extern char* SESSION_ID;  // From your existing code
  if (SESSION_ID != nullptr) {
    url += "&session_id=" + String(SESSION_ID);
  }
  
  logSD("INFO", ("HTTP POST to: " + url).c_str());
  logSD("INFO", ("Payload size: " + String(fb->len) + " bytes").c_str());
  
  http.setTimeout(30000);
  http.begin(url);
  http.addHeader("Content-Type", "image/jpeg");
  http.addHeader("X-ESP32-CAM", "true");
  
  int httpCode = http.POST(fb->buf, fb->len);
  
  bool success = false;
  
  if (httpCode == 200) {
    String response = http.getString();
    logSD("INFO", ("HTTP 200: " + response).c_str());
    
    // Parse JSON response
    StaticJsonDocument<256> doc;
    DeserializationError error = deserializeJson(doc, response);
    
    if (!error && doc["ok"] == true) {
      success = true;
      
      // Extract session_id from response
      const char* sid = doc["sid"];
      if (sid && SESSION_ID == nullptr) {
        SESSION_ID = strdup(sid);
        logSD("INFO", ("Session ID stored: " + String(sid)).c_str());
      }
    }
  } else if (httpCode > 0) {
    logSD("ERROR", ("HTTP error: " + String(httpCode)).c_str());
    String response = http.getString();
    logSD("ERROR", response.c_str());
  } else {
    logSD("ERROR", ("HTTP connection failed: " + String(http.errorToString(httpCode).c_str())).c_str());
    
    // Mark backend as potentially down
    backendRegistered = false;
  }
  
  http.end();
  return success;
}

// ============================================================
// UPDATED: uploadTelemetryToBackend() uses dynamic IP
// ============================================================

bool uploadTelemetryToBackend(const char* csvData) {
  HTTPClient http;
  String url = "http://" + PC_BACKEND_IP + ":" + String(PC_BACKEND_PORT) + 
               "/api/v1/photos/esp32-telemetry";
  
  http.setTimeout(5000);
  http.begin(url);
  http.addHeader("Content-Type", "text/plain");
  
  int httpCode = http.POST(csvData);
  bool success = (httpCode == 200);
  
  if (!success) {
    logSD("WARNING", ("Telemetry upload failed: " + String(httpCode)).c_str());
    if (httpCode < 0) {
      backendRegistered = false;  // Connection failed
    }
  }
  
  http.end();
  return success;
}

// ============================================================
// INTEGRATION: Add these to your server setup
// ============================================================

void setupBackendRegistrationEndpoints() {
  // POST /api/config/backend-ip - Register backend IP
  server.on("/api/config/backend-ip", HTTP_POST, [](AsyncWebServerRequest *request){}, NULL, handleBackendConfig);
  
  // GET /api/config/backend-ip - Check current backend IP
  server.on("/api/config/backend-ip", HTTP_GET, handleGetBackendConfig);
  
  // CORS preflight
  server.on("/api/config/backend-ip", HTTP_OPTIONS, [](AsyncWebServerRequest *request) {
    AsyncWebServerResponse *response = request->beginResponse(200);
    response->addHeader("Access-Control-Allow-Origin", "*");
    response->addHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
    response->addHeader("Access-Control-Allow-Headers", "Content-Type");
    request->send(response);
  });
  
  logSD("INFO", "Backend registration endpoints ready");
}

// ============================================================
// HELPER: Periodic backend health check
// ============================================================

void checkBackendHealth() {
  if (millis() - lastBackendCheck < 30000) return;  // Check every 30s
  lastBackendCheck = millis();
  
  HTTPClient http;
  String url = "http://" + PC_BACKEND_IP + ":" + String(PC_BACKEND_PORT) + "/health";
  
  http.setTimeout(3000);
  http.begin(url);
  
  int httpCode = http.GET();
  if (httpCode == 200) {
    if (!backendRegistered) {
      logSD("INFO", "Backend connection restored");
    }
    backendRegistered = true;
  } else {
    if (backendRegistered) {
      logSD("WARNING", ("Backend health check failed: " + String(httpCode)).c_str());
    }
    backendRegistered = false;
  }
  
  http.end();
}
