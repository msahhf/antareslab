/**
 * AntaresStudio IoT - ESP32-CAM Ana Program
 * 
 * Görevler:
 *   1. Wi-Fi bağlantısı ve mDNS servis yayını
 *   2. OTA güncelleme desteği (ESP32 kendi firmware'i)
 *   3. UART Bridge modu (Arduino firmware güncelleme)
 *   4. Kamera ile fotoğraf çekimi
 *   5. HTTP API sunucusu
 */

#include <Arduino.h>
#include <WiFi.h>
#include <ESPmDNS.h>
#include <ArduinoOTA.h>
#include <ESPAsyncWebServer.h>
#include <ArduinoJson.h>
#include <Update.h>

#include "config.h"
#include "uart_bridge.h"
#include "camera_manager.h"

// ============================================================
// Global Nesneler
// ============================================================
AsyncWebServer server(80);
UARTBridge uartBridge;
CameraManager cameraManager;

// Durum değişkenleri
bool wifiConnected = false;
bool bridgeModeActive = false;
unsigned long lastStatusPrint = 0;

// ============================================================
// Wi-Fi Bağlantısı
// ============================================================
bool setupWiFi() {
    Serial.println("[WiFi] Bağlanılıyor...");
    Serial.printf("[WiFi] SSID: %s\n", WIFI_SSID);
    
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    
    unsigned long startTime = millis();
    while (WiFi.status() != WL_CONNECTED) {
        if (millis() - startTime > WIFI_CONNECT_TIMEOUT_MS) {
            Serial.println("[WiFi] HATA: Bağlantı zaman aşımı!");
            return false;
        }
        delay(WIFI_RETRY_DELAY_MS);
        Serial.print(".");
    }
    
    Serial.println();
    Serial.printf("[WiFi] Bağlandı! IP: %s\n", WiFi.localIP().toString().c_str());
    Serial.printf("[WiFi] RSSI: %d dBm\n", WiFi.RSSI());
    
    wifiConnected = true;
    return true;
}

// ============================================================
// mDNS Servisi
// ============================================================
bool setupMDNS() {
    if (!MDNS.begin(MDNS_HOSTNAME)) {
        Serial.println("[mDNS] HATA: Servis başlatılamadı!");
        return false;
    }
    
    // Servis kaydı - Flutter uygulamasının cihazı bulması için
    MDNS.addService(MDNS_SERVICE_NAME, MDNS_SERVICE_PROTO, MDNS_SERVICE_PORT);
    MDNS.addServiceTxt(MDNS_SERVICE_NAME, MDNS_SERVICE_PROTO, "version", FW_VERSION_STRING);
    MDNS.addServiceTxt(MDNS_SERVICE_NAME, MDNS_SERVICE_PROTO, "device", "esp32cam");
    MDNS.addServiceTxt(MDNS_SERVICE_NAME, MDNS_SERVICE_PROTO, "project", "AntaresStudio");
    
    Serial.printf("[mDNS] Hostname: %s.local\n", MDNS_HOSTNAME);
    Serial.printf("[mDNS] Servis: %s.%s, Port: %d\n", 
                  MDNS_SERVICE_NAME, MDNS_SERVICE_PROTO, MDNS_SERVICE_PORT);
    
    return true;
}

// ============================================================
// OTA Güncelleme (ESP32 kendi firmware'i)
// ============================================================
void setupOTA() {
    ArduinoOTA.setHostname(MDNS_HOSTNAME);
    ArduinoOTA.setPassword(OTA_PASSWORD);
    ArduinoOTA.setPort(OTA_PORT);
    
    ArduinoOTA.onStart([]() {
        String type = (ArduinoOTA.getCommand() == U_FLASH) ? "firmware" : "filesystem";
        Serial.printf("[OTA] Güncelleme başlıyor: %s\n", type.c_str());
        // Kamerayı kapat, bellek boşalt
        cameraManager.deinit();
    });
    
    ArduinoOTA.onEnd([]() {
        Serial.println("\n[OTA] Güncelleme tamamlandı! Yeniden başlatılıyor...");
    });
    
    ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
        Serial.printf("[OTA] İlerleme: %u%%\r", (progress / (total / 100)));
    });
    
    ArduinoOTA.onError([](ota_error_t error) {
        Serial.printf("[OTA] HATA [%u]: ", error);
        switch (error) {
            case OTA_AUTH_ERROR:    Serial.println("Kimlik doğrulama hatası"); break;
            case OTA_BEGIN_ERROR:   Serial.println("Başlatma hatası"); break;
            case OTA_CONNECT_ERROR: Serial.println("Bağlantı hatası"); break;
            case OTA_RECEIVE_ERROR: Serial.println("Alma hatası"); break;
            case OTA_END_ERROR:     Serial.println("Bitiş hatası"); break;
        }
    });
    
    ArduinoOTA.begin();
    Serial.printf("[OTA] Hazır. Port: %d\n", OTA_PORT);
}

// ============================================================
// HTTP API Endpoint'leri
// ============================================================
void setupHTTPServer() {
    
    // --- Durum Bilgisi ---
    server.on("/api/status", HTTP_GET, [](AsyncWebServerRequest *request) {
        StaticJsonDocument<512> doc;
        doc["device"]       = "ESP32-CAM";
        doc["firmware"]     = FW_VERSION_STRING;
        doc["wifi_rssi"]    = WiFi.RSSI();
        doc["ip"]           = WiFi.localIP().toString();
        doc["bridge_mode"]  = bridgeModeActive;
        doc["heap_free"]    = ESP.getFreeHeap();
        doc["psram_free"]   = ESP.getFreePsram();
        doc["uptime_sec"]   = millis() / 1000;
        
        String response;
        serializeJson(doc, response);
        request->send(200, "application/json", response);
    });
    
    // --- ESP32 Firmware Güncelleme (HTTP üzerinden) ---
    server.on("/api/ota/esp32", HTTP_POST, 
        // Tamamlanma callback'i
        [](AsyncWebServerRequest *request) {
            bool success = !Update.hasError();
            StaticJsonDocument<128> doc;
            doc["success"] = success;
            doc["message"] = success ? "ESP32 güncelleme başarılı, yeniden başlatılıyor..." 
                                     : "ESP32 güncelleme başarısız!";
            String response;
            serializeJson(doc, response);
            request->send(success ? 200 : 500, "application/json", response);
            
            if (success) {
                delay(1000);
                ESP.restart();
            }
        },
        // Upload handler
        [](AsyncWebServerRequest *request, const String& filename, 
           size_t index, uint8_t *data, size_t len, bool final) {
            
            if (index == 0) {
                Serial.printf("[OTA-HTTP] ESP32 güncelleme başlıyor: %s\n", filename.c_str());
                cameraManager.deinit();  // Bellek boşalt
                
                if (!Update.begin(UPDATE_SIZE_UNKNOWN)) {
                    Update.printError(Serial);
                    return;
                }
            }
            
            if (len) {
                if (Update.write(data, len) != len) {
                    Update.printError(Serial);
                    return;
                }
                Serial.printf("[OTA-HTTP] İlerleme: %u bytes\r", index + len);
            }
            
            if (final) {
                if (Update.end(true)) {
                    Serial.printf("\n[OTA-HTTP] Toplam: %u bytes\n", index + len);
                } else {
                    Update.printError(Serial);
                }
            }
        }
    );
    
    // --- Arduino Firmware Güncelleme (UART Bridge) ---
    server.on("/api/ota/arduino", HTTP_POST,
        // Tamamlanma callback'i
        [](AsyncWebServerRequest *request) {
            bridgeModeActive = false;
            uartBridge.endBridge();
            
            StaticJsonDocument<128> doc;
            doc["success"] = true;
            doc["message"] = "Arduino güncelleme tamamlandı.";
            String response;
            serializeJson(doc, response);
            request->send(200, "application/json", response);
        },
        // Upload handler - her chunk UART'a bridge edilir
        [](AsyncWebServerRequest *request, const String& filename,
           size_t index, uint8_t *data, size_t len, bool final) {
            
            if (index == 0) {
                Serial.printf("[Bridge] Arduino güncelleme başlıyor: %s\n", filename.c_str());
                bridgeModeActive = true;
                
                // Arduino'yu resetle ve bridge modunu başlat
                if (!uartBridge.beginBridge()) {
                    Serial.println("[Bridge] HATA: Bridge modu başlatılamadı!");
                    return;
                }
            }
            
            if (len) {
                // Gelen veriyi UART üzerinden Arduino'ya ilet
                uartBridge.forwardData(data, len);
                Serial.printf("[Bridge] İletilen: %u bytes\r", index + len);
            }
            
            if (final) {
                Serial.printf("\n[Bridge] Toplam: %u bytes iletildi\n", index + len);
            }
        }
    );
    
    // --- Fotoğraf Çekimi ---
    server.on("/api/capture", HTTP_GET, [](AsyncWebServerRequest *request) {
        if (bridgeModeActive) {
            request->send(503, "application/json", 
                         "{\"error\":\"Bridge modu aktif, kamera kullanılamaz\"}");
            return;
        }
        
        camera_fb_t* fb = cameraManager.capture();
        if (!fb) {
            request->send(500, "application/json", 
                         "{\"error\":\"Fotoğraf çekilemedi\"}");
            return;
        }
        
        // JPEG olarak gönder
        AsyncWebServerResponse *response = request->beginResponse_P(
            200, "image/jpeg", fb->buf, fb->len);
        response->addHeader("Content-Disposition", "inline; filename=capture.jpg");
        request->send(response);
        
        cameraManager.release(fb);
    });
    
    // CORS desteği
    DefaultHeaders::Instance().addHeader("Access-Control-Allow-Origin", "*");
    DefaultHeaders::Instance().addHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    DefaultHeaders::Instance().addHeader("Access-Control-Allow-Headers", "Content-Type");
    
    server.begin();
    Serial.println("[HTTP] Sunucu başlatıldı, port: 80");
}

// ============================================================
// SETUP
// ============================================================
void setup() {
    Serial.begin(115200);
    delay(1000);
    
    Serial.println();
    Serial.println("╔══════════════════════════════════════╗");
    Serial.println("║   AntaresStudio IoT - ESP32-CAM     ║");
    Serial.printf( "║   Firmware v%s                   ║\n", FW_VERSION_STRING);
    Serial.println("╚══════════════════════════════════════╝");
    Serial.println();
    
    // LED durumu
    pinMode(LED_BUILTIN_PIN, OUTPUT);
    digitalWrite(LED_BUILTIN_PIN, HIGH);  // LOW = açık (aktif düşük)
    
    // 1. Kamera başlat
    if (cameraManager.init()) {
        Serial.println("[Camera] Kamera hazır.");
    } else {
        Serial.println("[Camera] HATA: Kamera başlatılamadı!");
    }
    
    // 2. UART Bridge hazırla (henüz aktif değil)
    uartBridge.init();
    Serial.println("[Bridge] UART Bridge hazır (bekleme modunda).");
    
    // 3. Wi-Fi bağlan
    if (!setupWiFi()) {
        Serial.println("[HATA] Wi-Fi bağlantısı kurulamadı! Yeniden başlatılıyor...");
        delay(3000);
        ESP.restart();
    }
    
    // 4. mDNS başlat
    setupMDNS();
    
    // 5. OTA başlat
    setupOTA();
    
    // 6. HTTP sunucusu başlat
    setupHTTPServer();
    
    // Hazır
    digitalWrite(LED_BUILTIN_PIN, LOW);
    Serial.println();
    Serial.println("[SİSTEM] Tüm servisler hazır!");
    Serial.printf("[SİSTEM] Web: http://%s.local\n", MDNS_HOSTNAME);
    Serial.println();
}

// ============================================================
// LOOP
// ============================================================
void loop() {
    // OTA kontrol
    ArduinoOTA.handle();
    
    // Bridge modu aktifse, UART verilerini yönet
    if (bridgeModeActive) {
        uartBridge.handleBridge();
        
        // Timeout kontrolü
        if (uartBridge.isTimedOut()) {
            Serial.println("[Bridge] Zaman aşımı! Bridge modu kapatılıyor.");
            bridgeModeActive = false;
            uartBridge.endBridge();
        }
    }
    
    // Durum yazdırma (her 30 saniyede)
    if (millis() - lastStatusPrint > 30000) {
        lastStatusPrint = millis();
        Serial.printf("[Durum] Heap: %u, PSRAM: %u, RSSI: %d dBm\n",
                      ESP.getFreeHeap(), ESP.getFreePsram(), WiFi.RSSI());
    }
    
    delay(10);
}
