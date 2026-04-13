/**
 * AntaresStudio IoT - Kamera Yöneticisi
 * 
 * ESP32-CAM OV2640 kamera modülü kontrolü.
 * Fotoğraf çekimi ve backend'e gönderim.
 */

#ifndef CAMERA_MANAGER_H
#define CAMERA_MANAGER_H

#include <Arduino.h>
#include "esp_camera.h"
#include "config.h"

// ESP32-CAM (AI-Thinker modeli) pin tanımları
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22

class CameraManager {
public:
    /**
     * Kamerayı başlat.
     * @return true başarılı ise
     */
    bool init() {
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
        
        // PSRAM varsa yüksek çözünürlük
        if (psramFound()) {
            config.frame_size   = CAMERA_FRAME_SIZE;
            config.jpeg_quality = CAMERA_QUALITY;
            config.fb_count     = 2;
            Serial.println("[Camera] PSRAM bulundu, yüksek çözünürlük aktif.");
        } else {
            config.frame_size   = FRAMESIZE_SVGA;
            config.jpeg_quality = 12;
            config.fb_count     = 1;
            Serial.println("[Camera] PSRAM bulunamadı, düşük çözünürlük.");
        }
        
        esp_err_t err = esp_camera_init(&config);
        if (err != ESP_OK) {
            Serial.printf("[Camera] HATA: Başlatma hatası 0x%x\n", err);
            _initialized = false;
            return false;
        }
        
        // Kamera ayarlarını optimize et
        sensor_t *sensor = esp_camera_sensor_get();
        if (sensor) {
            sensor->set_brightness(sensor, 0);
            sensor->set_contrast(sensor, 0);
            sensor->set_saturation(sensor, 0);
            sensor->set_whitebal(sensor, 1);
            sensor->set_awb_gain(sensor, 1);
            sensor->set_wb_mode(sensor, 0);
            sensor->set_exposure_ctrl(sensor, 1);
            sensor->set_aec2(sensor, 0);
            sensor->set_gain_ctrl(sensor, 1);
        }
        
        _initialized = true;
        return true;
    }
    
    /**
     * Kamerayı durdur.
     * OTA güncellemesi öncesi bellek boşaltmak için kullanılır.
     */
    void deinit() {
        if (_initialized) {
            esp_camera_deinit();
            _initialized = false;
            Serial.println("[Camera] Kamera durduruldu.");
        }
    }
    
    /**
     * Fotoğraf çek.
     * @return Frame buffer pointer, kullanım sonrası release() çağrılmalı
     */
    camera_fb_t* capture() {
        if (!_initialized) {
            Serial.println("[Camera] HATA: Kamera başlatılmamış!");
            return nullptr;
        }
        
        camera_fb_t *fb = esp_camera_fb_get();
        if (!fb) {
            Serial.println("[Camera] HATA: Frame yakalanamadı!");
            return nullptr;
        }
        
        Serial.printf("[Camera] Çekim: %dx%d, %u bytes, format: %d\n",
                      fb->width, fb->height, fb->len, fb->format);
        
        return fb;
    }
    
    /**
     * Frame buffer'ını serbest bırak.
     * @param fb Serbest bırakılacak frame buffer
     */
    void release(camera_fb_t* fb) {
        if (fb) {
            esp_camera_fb_return(fb);
        }
    }
    
    /**
     * Kamera durumu.
     */
    bool isInitialized() const {
        return _initialized;
    }

private:
    bool _initialized = false;
};

#endif // CAMERA_MANAGER_H
