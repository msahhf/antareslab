/**
 * AntaresStudio IoT - UART Bridge (Serial Bridge)
 * 
 * ESP32-CAM üzerinden Arduino'yu programlama desteği.
 * 
 * Çalışma prensibi:
 *   1. Flutter App, GitHub'dan Arduino .hex dosyasını indirir.
 *   2. App, HTTP POST ile .hex verisini ESP32-CAM'e gönderir.
 *   3. ESP32-CAM, Arduino RESET pinini LOW'a çekerek bootloader moduna sokar.
 *   4. Gelen veri transparent olarak UART (TX/RX) üzerinden Arduino'ya iletilir.
 *   5. STK500 protokolü ile Arduino bootloader'a firmware yazılır.
 *   6. İşlem bitince bridge modu kapatılır, Arduino normal çalışmaya döner.
 * 
 * Donanım bağlantısı:
 *   ESP32 GPIO14 (TX) --> Arduino RX
 *   ESP32 GPIO15 (RX) --> Arduino TX
 *   ESP32 GPIO12      --> Arduino RESET (aktif LOW)
 */

#ifndef UART_BRIDGE_H
#define UART_BRIDGE_H

#include <Arduino.h>
#include "config.h"

class UARTBridge {
public:
    /**
     * Bridge modülünü başlat (pin modlarını ayarla).
     * setup() içinde çağrılır, henüz bridge aktifleşmez.
     */
    void init() {
        // Arduino RESET pini - normalde HIGH (aktif değil)
        pinMode(ARDUINO_RESET_PIN, OUTPUT);
        digitalWrite(ARDUINO_RESET_PIN, HIGH);
        
        _bridgeActive = false;
        _lastActivityTime = 0;
        _totalBytesForwarded = 0;
    }
    
    /**
     * Bridge modunu başlat.
     * Arduino'yu resetleyerek bootloader moduna sokar ve UART'ı açar.
     * 
     * @return true başarılı ise
     */
    bool beginBridge() {
        Serial.println("[Bridge] Başlatılıyor...");
        
        // 1. UART2'yi Arduino ile haberleşme için aç
        Serial2.begin(UART_BRIDGE_BAUD, SERIAL_8N1, UART_RX_PIN, UART_TX_PIN);
        Serial.printf("[Bridge] UART açıldı: %d baud, TX=%d, RX=%d\n", 
                      UART_BRIDGE_BAUD, UART_TX_PIN, UART_RX_PIN);
        
        // 2. Arduino'yu resetle (bootloader moduna sok)
        resetArduino();
        
        // 3. Bridge durumunu aktif et
        _bridgeActive = true;
        _lastActivityTime = millis();
        _totalBytesForwarded = 0;
        
        // 4. Bootloader senkronizasyonu bekle
        Serial.println("[Bridge] Arduino bootloader bekleniyor...");
        delay(BRIDGE_RESET_WAIT_MS);
        
        // Bootloader'dan gelen veriyi temizle
        while (Serial2.available()) {
            Serial2.read();
        }
        
        Serial.println("[Bridge] Bridge modu AKTİF.");
        return true;
    }
    
    /**
     * Veriyi UART üzerinden Arduino'ya ilet.
     * HTTP upload handler'dan çağrılır.
     * 
     * @param data  Veri buffer'ı
     * @param len   Veri uzunluğu
     * @return İletilen byte sayısı
     */
    size_t forwardData(const uint8_t* data, size_t len) {
        if (!_bridgeActive) {
            Serial.println("[Bridge] UYARI: Bridge aktif değil, veri iletilmedi.");
            return 0;
        }
        
        _lastActivityTime = millis();
        
        // Veriyi chunk'lar halinde gönder (buffer taşmasını önle)
        size_t totalSent = 0;
        size_t remaining = len;
        
        while (remaining > 0) {
            size_t chunkSize = min(remaining, (size_t)BRIDGE_CHUNK_SIZE);
            size_t sent = Serial2.write(data + totalSent, chunkSize);
            Serial2.flush();  // TX buffer'ın boşalmasını bekle
            
            totalSent += sent;
            remaining -= sent;
            
            // Arduino'dan yanıt bekle (STK500 protokolü)
            _waitForResponse(50);  // 50ms timeout
        }
        
        _totalBytesForwarded += totalSent;
        return totalSent;
    }
    
    /**
     * Bridge loop handler.
     * UART'tan gelen Arduino yanıtlarını işler.
     * Ana loop'tan çağrılır.
     */
    void handleBridge() {
        if (!_bridgeActive) return;
        
        // Arduino'dan gelen yanıtları oku ve logla
        while (Serial2.available()) {
            uint8_t byte = Serial2.read();
            _lastActivityTime = millis();
            
            // STK500 yanıtlarını logla
            if (byte == STK500_RESP_INSYNC) {
                Serial.print("[Bridge] Arduino: IN_SYNC ");
            } else if (byte == STK500_RESP_OK) {
                Serial.println("OK");
            }
        }
    }
    
    /**
     * Bridge modunu sonlandır.
     * Arduino'yu resetler ve UART'ı kapatır.
     */
    void endBridge() {
        Serial.printf("[Bridge] Kapatılıyor. Toplam iletilen: %u bytes\n", 
                      _totalBytesForwarded);
        
        _bridgeActive = false;
        
        // UART'ı kapat
        Serial2.end();
        
        // Arduino'yu resetle (normal çalışma moduna dön)
        resetArduino();
        
        Serial.println("[Bridge] Bridge modu KAPALI. Arduino yeniden başlatıldı.");
    }
    
    /**
     * Timeout kontrolü.
     * @return true eğer bridge modu timeout olduysa
     */
    bool isTimedOut() const {
        if (!_bridgeActive) return false;
        return (millis() - _lastActivityTime) > BRIDGE_TIMEOUT_MS;
    }
    
    /**
     * Bridge durumu.
     * @return true eğer bridge modu aktifse
     */
    bool isActive() const {
        return _bridgeActive;
    }
    
    /**
     * Toplam iletilen byte sayısı.
     */
    uint32_t getTotalBytesForwarded() const {
        return _totalBytesForwarded;
    }

private:
    bool _bridgeActive;
    unsigned long _lastActivityTime;
    uint32_t _totalBytesForwarded;
    
    /**
     * Arduino'yu resetle.
     * RESET pinini LOW-HIGH yaparak bootloader'ı tetikler.
     */
    void resetArduino() {
        Serial.println("[Bridge] Arduino RESET...");
        digitalWrite(ARDUINO_RESET_PIN, LOW);
        delay(BRIDGE_RESET_PULSE_MS);
        digitalWrite(ARDUINO_RESET_PIN, HIGH);
        delay(BRIDGE_RESET_WAIT_MS);
        Serial.println("[Bridge] Arduino RESET tamamlandı.");
    }
    
    /**
     * Arduino'dan yanıt bekle.
     * @param timeoutMs Maksimum bekleme süresi
     */
    void _waitForResponse(uint32_t timeoutMs) {
        unsigned long start = millis();
        while (millis() - start < timeoutMs) {
            if (Serial2.available()) {
                uint8_t resp = Serial2.read();
                if (resp == STK500_RESP_INSYNC) {
                    // Bootloader senkronize
                    break;
                }
            }
            delay(1);
        }
    }
};

#endif // UART_BRIDGE_H
