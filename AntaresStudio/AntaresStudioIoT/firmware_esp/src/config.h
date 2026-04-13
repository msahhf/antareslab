/**
 * AntaresStudio IoT - ESP32-CAM Konfigürasyon
 * 
 * Tüm sabit değerler ve pin tanımlamaları burada yapılır.
 */

#ifndef CONFIG_H
#define CONFIG_H

// ============================================================
// Wi-Fi Ayarları
// ============================================================
#define WIFI_SSID          "AntaresStudio"
#define WIFI_PASSWORD      "antares2026"
#define WIFI_CONNECT_TIMEOUT_MS  15000
#define WIFI_RETRY_DELAY_MS      1000

// ============================================================
// mDNS Ayarları
// ============================================================
#define MDNS_HOSTNAME      "antares-scanner"    // antares-scanner.local
#define MDNS_SERVICE_NAME  "_antares"
#define MDNS_SERVICE_PROTO "_tcp"
#define MDNS_SERVICE_PORT  80

// ============================================================
// OTA Ayarları
// ============================================================
#define OTA_PASSWORD       "antares_ota_2026"
#define OTA_PORT           3232

// ============================================================
// UART Bridge Ayarları (Arduino Programlama)
// ============================================================
#define UART_BRIDGE_BAUD   115200    // Arduino bootloader baud rate
#define UART_TX_PIN        14       // ESP32 TX -> Arduino RX
#define UART_RX_PIN        15       // ESP32 RX -> Arduino TX
#define ARDUINO_RESET_PIN  12       // ESP32 GPIO -> Arduino RESET

// Bridge zamanlama
#define BRIDGE_RESET_PULSE_MS    100     // Reset pulse süresi
#define BRIDGE_RESET_WAIT_MS     500     // Reset sonrası bekleme
#define BRIDGE_TIMEOUT_MS        60000   // Bridge modu timeout (60s)
#define BRIDGE_CHUNK_SIZE        128     // Her seferlik veri boyutu

// STK500 Protocol sabitleri
#define STK500_CMD_SIGN_ON       0x01
#define STK500_CMD_GET_SYNC      0x30
#define STK500_CMD_SET_DEVICE    0x42
#define STK500_CMD_LOAD_ADDRESS  0x55
#define STK500_CMD_PROG_PAGE     0x64
#define STK500_CMD_READ_PAGE     0x74
#define STK500_CMD_LEAVE_PROGMODE 0x51
#define STK500_RESP_INSYNC       0x14
#define STK500_RESP_OK           0x10

// ============================================================
// Kamera Ayarları
// ============================================================
#define CAMERA_FRAME_SIZE  FRAMESIZE_UXGA   // 1600x1200
#define CAMERA_QUALITY     10               // JPEG kalitesi (0-63, düşük=yüksek kalite)

// ============================================================
// Backend Ayarları
// ============================================================
#define BACKEND_HOST       "192.168.1.100"
#define BACKEND_PORT       8000
#define BACKEND_UPLOAD_PATH "/api/v1/photos/upload"

// ============================================================
// LED Ayarları
// ============================================================
#define LED_BUILTIN_PIN    33       // ESP32-CAM dahili LED
#define FLASH_LED_PIN      4        // ESP32-CAM flash LED

// ============================================================
// Firmware Versiyon
// ============================================================
#define FW_VERSION_MAJOR   0
#define FW_VERSION_MINOR   1
#define FW_VERSION_PATCH   0
#define FW_VERSION_STRING  "0.1.0"

#endif // CONFIG_H
