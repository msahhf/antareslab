#include <WiFi.h>
#include <WebServer.h>

// Wi-Fi Ağ Ayarları
const char* ssid = "Antares_Test_Agi";
const char* password = "antares-test";

// Sabit IP Ayarları (192.168.1.1 için)
IPAddress local_IP(192, 168, 1, 1);
IPAddress gateway(192, 168, 1, 1);
IPAddress subnet(255, 255, 255, 0);

WebServer server(80);

void handleRoot() {
  server.send(200, "text/plain", "Hello World");
}

void setup() {
  Serial.begin(115200);

  // Sabit IP Yapılandırması
  if (!WiFi.softAPConfig(local_IP, gateway, subnet)) {
    Serial.println("AP Yapılandırma Hatası!");
  }

  // Access Point Başlatma
  WiFi.softAP(ssid, password);
  
  Serial.println("ESP32 Test Agi Baslatildi");
  Serial.print("IP Adresi: ");
  Serial.println(WiFi.softAPIP());

  // Sunucu Rotaları
  server.on("/", handleRoot);
  
  server.begin();
  Serial.println("Web Sunucusu Baslatildi.");
}

void loop() {
  server.handleClient();
}