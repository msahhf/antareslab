/**
 * AntaresStudio IoT - Arduino Nano Firmware
 * 
 * Sensör kontrolü ve ESP32-CAM ile UART haberleşme.
 * 
 * Görevler:
 *   - Döner tabla motor kontrolü (Step motor)
 *   - ToF mesafe sensörü okuma
 *   - IMU (ivmeölçer/jiroskop) okuma
 *   - ESP32-CAM'e komut/veri gönderimi (UART)
 * 
 * UART Protokolü (ESP32 ile):
 *   Komut formatı: <CMD_ID, PARAM1, PARAM2, ...>
 *   Yanıt formatı: [STATUS, DATA1, DATA2, ...]
 */

#include <Arduino.h>
#include <Wire.h>

// ============================================================
// Pin Tanımları
// ============================================================
// Step Motor (A4988 Driver)
#define MOTOR_STEP_PIN      3
#define MOTOR_DIR_PIN       4
#define MOTOR_ENABLE_PIN    5
#define MOTOR_MS1_PIN       6
#define MOTOR_MS2_PIN       7

// Endstop (Home pozisyonu)
#define ENDSTOP_PIN         8

// LED göstergeler
#define LED_STATUS_PIN      13

// ============================================================
// Sabitler
// ============================================================
#define SERIAL_BAUD         115200

// Motor parametreleri
#define STEPS_PER_REV       200     // 1.8° step motor
#define MICROSTEP_FACTOR    8       // 1/8 microstepping
#define TOTAL_STEPS_PER_REV (STEPS_PER_REV * MICROSTEP_FACTOR)  // 1600
#define DEFAULT_STEP_DELAY  800     // us (mikrosaniye)

// Tarama parametreleri
#define SCAN_POSITIONS      36      // 360° / 36 = 10° adımlar
#define STEPS_PER_POSITION  (TOTAL_STEPS_PER_REV / SCAN_POSITIONS)

// UART Komutları
#define CMD_STATUS          'S'     // Durum sorgula
#define CMD_HOME            'H'     // Home pozisyonuna git
#define CMD_ROTATE          'R'     // Belirli açıya dön
#define CMD_SCAN_START      'G'     // Otomatik tarama başlat
#define CMD_SCAN_STOP       'X'     // Taramayı durdur
#define CMD_MOTOR_ENABLE    'E'     // Motoru etkinleştir
#define CMD_MOTOR_DISABLE   'D'     // Motoru devre dışı bırak
#define CMD_SET_SPEED       'V'     // Hız ayarla

// Yanıt kodları
#define RESP_OK             "OK"
#define RESP_ERROR          "ERR"
#define RESP_READY          "RDY"
#define RESP_POSITION       "POS"
#define RESP_CAPTURE        "CAP"   // Fotoğraf çek komutu (ESP32'ye)

// ============================================================
// Global Değişkenler
// ============================================================
long currentPosition = 0;           // Mevcut step pozisyonu
int stepDelay = DEFAULT_STEP_DELAY; // Step gecikmesi (us)
bool motorEnabled = false;
bool scanActive = false;
int scanStep = 0;
bool isHomed = false;

// UART buffer
char cmdBuffer[64];
int cmdIndex = 0;
bool cmdReady = false;

// ============================================================
// Motor Kontrol Fonksiyonları
// ============================================================

void motorEnable(bool enable) {
    digitalWrite(MOTOR_ENABLE_PIN, enable ? LOW : HIGH);  // A4988: LOW = aktif
    motorEnabled = enable;
}

void setMicrostepping(int factor) {
    // A4988 microstepping ayarları
    switch (factor) {
        case 1:  // Full step
            digitalWrite(MOTOR_MS1_PIN, LOW);
            digitalWrite(MOTOR_MS2_PIN, LOW);
            break;
        case 2:  // Half step
            digitalWrite(MOTOR_MS1_PIN, HIGH);
            digitalWrite(MOTOR_MS2_PIN, LOW);
            break;
        case 4:  // Quarter step
            digitalWrite(MOTOR_MS1_PIN, LOW);
            digitalWrite(MOTOR_MS2_PIN, HIGH);
            break;
        case 8:  // Eighth step
            digitalWrite(MOTOR_MS1_PIN, HIGH);
            digitalWrite(MOTOR_MS2_PIN, HIGH);
            break;
    }
}

void stepMotor(int steps, bool direction) {
    if (!motorEnabled) {
        motorEnable(true);
        delay(10);
    }
    
    digitalWrite(MOTOR_DIR_PIN, direction ? HIGH : LOW);
    
    for (int i = 0; i < abs(steps); i++) {
        digitalWrite(MOTOR_STEP_PIN, HIGH);
        delayMicroseconds(stepDelay);
        digitalWrite(MOTOR_STEP_PIN, LOW);
        delayMicroseconds(stepDelay);
        
        // Pozisyon takibi
        currentPosition += direction ? 1 : -1;
    }
}

void homeMotor() {
    Serial.println("[Motor] Home aranıyor...");
    motorEnable(true);
    
    // Endstop'a doğru dön
    while (digitalRead(ENDSTOP_PIN) == HIGH) {
        stepMotor(1, false);  // Geri dön
        delay(1);
    }
    
    // Biraz geri çekil
    stepMotor(50, true);
    delay(100);
    
    // Yavaşça tekrar endstop'a
    stepDelay = DEFAULT_STEP_DELAY * 2;  // Yavaş
    while (digitalRead(ENDSTOP_PIN) == HIGH) {
        stepMotor(1, false);
        delay(2);
    }
    stepDelay = DEFAULT_STEP_DELAY;
    
    currentPosition = 0;
    isHomed = true;
    Serial.println("[Motor] Home bulundu!");
}

void rotateToAngle(float degrees) {
    long targetSteps = (long)(degrees / 360.0 * TOTAL_STEPS_PER_REV);
    long delta = targetSteps - currentPosition;
    
    if (delta == 0) return;
    
    bool direction = delta > 0;
    stepMotor(abs(delta), direction);
    
    Serial.print("[Motor] Açı: ");
    Serial.print(degrees);
    Serial.print("° (Step: ");
    Serial.print(currentPosition);
    Serial.println(")");
}

// ============================================================
// UART Komut İşleme
// ============================================================

void processCommand(const char* cmd) {
    char cmdType = cmd[0];
    
    switch (cmdType) {
        case CMD_STATUS: {
            // Durum bilgisi gönder
            Serial.print("[");
            Serial.print(RESP_OK);
            Serial.print(",");
            Serial.print(currentPosition);
            Serial.print(",");
            Serial.print(motorEnabled ? 1 : 0);
            Serial.print(",");
            Serial.print(isHomed ? 1 : 0);
            Serial.print(",");
            Serial.print(scanActive ? 1 : 0);
            Serial.println("]");
            break;
        }
        
        case CMD_HOME: {
            homeMotor();
            Serial.print("[");
            Serial.print(RESP_OK);
            Serial.println(",HOMED]");
            break;
        }
        
        case CMD_ROTATE: {
            // Format: R,açı  (örn: R,90.0)
            float angle = 0;
            if (strlen(cmd) > 2) {
                angle = atof(cmd + 2);
            }
            rotateToAngle(angle);
            Serial.print("[");
            Serial.print(RESP_OK);
            Serial.print(",");
            Serial.print(RESP_POSITION);
            Serial.print(",");
            Serial.print(angle);
            Serial.println("]");
            break;
        }
        
        case CMD_SCAN_START: {
            if (!isHomed) {
                Serial.print("[");
                Serial.print(RESP_ERROR);
                Serial.println(",NOT_HOMED]");
                break;
            }
            scanActive = true;
            scanStep = 0;
            Serial.print("[");
            Serial.print(RESP_OK);
            Serial.println(",SCAN_START]");
            break;
        }
        
        case CMD_SCAN_STOP: {
            scanActive = false;
            scanStep = 0;
            Serial.print("[");
            Serial.print(RESP_OK);
            Serial.println(",SCAN_STOP]");
            break;
        }
        
        case CMD_MOTOR_ENABLE: {
            motorEnable(true);
            Serial.print("[");
            Serial.print(RESP_OK);
            Serial.println(",MOT_ON]");
            break;
        }
        
        case CMD_MOTOR_DISABLE: {
            motorEnable(false);
            Serial.print("[");
            Serial.print(RESP_OK);
            Serial.println(",MOT_OFF]");
            break;
        }
        
        case CMD_SET_SPEED: {
            // Format: V,delay_us
            if (strlen(cmd) > 2) {
                stepDelay = atoi(cmd + 2);
                stepDelay = constrain(stepDelay, 200, 5000);
            }
            Serial.print("[");
            Serial.print(RESP_OK);
            Serial.print(",SPD,");
            Serial.print(stepDelay);
            Serial.println("]");
            break;
        }
        
        default: {
            Serial.print("[");
            Serial.print(RESP_ERROR);
            Serial.println(",UNKNOWN_CMD]");
            break;
        }
    }
}

// ============================================================
// Otomatik Tarama Döngüsü
// ============================================================

void handleScan() {
    if (!scanActive) return;
    
    if (scanStep >= SCAN_POSITIONS) {
        // Tarama tamamlandı
        scanActive = false;
        scanStep = 0;
        
        // Home'a dön
        rotateToAngle(0);
        
        Serial.print("[");
        Serial.print(RESP_OK);
        Serial.println(",SCAN_DONE]");
        return;
    }
    
    // Mevcut pozisyona dön
    float angle = (float)scanStep * (360.0 / SCAN_POSITIONS);
    rotateToAngle(angle);
    
    // Titreşimin durmasını bekle
    delay(500);
    
    // ESP32-CAM'e fotoğraf çekme komutu gönder
    Serial.print("<");
    Serial.print(RESP_CAPTURE);
    Serial.print(",");
    Serial.print(scanStep);
    Serial.print(",");
    Serial.print(angle, 1);
    Serial.println(">");
    
    // Fotoğrafın çekilmesi için bekle
    delay(2000);
    
    scanStep++;
}

// ============================================================
// SETUP
// ============================================================
void setup() {
    Serial.begin(SERIAL_BAUD);
    
    // Pin modları
    pinMode(MOTOR_STEP_PIN, OUTPUT);
    pinMode(MOTOR_DIR_PIN, OUTPUT);
    pinMode(MOTOR_ENABLE_PIN, OUTPUT);
    pinMode(MOTOR_MS1_PIN, OUTPUT);
    pinMode(MOTOR_MS2_PIN, OUTPUT);
    pinMode(ENDSTOP_PIN, INPUT_PULLUP);
    pinMode(LED_STATUS_PIN, OUTPUT);
    
    // Motor başlangıç durumu
    motorEnable(false);
    setMicrostepping(MICROSTEP_FACTOR);
    
    // Başlangıç
    delay(500);
    Serial.println();
    Serial.println("================================");
    Serial.println(" AntaresStudio IoT - Arduino");
    Serial.println(" Firmware v0.1.0");
    Serial.println("================================");
    Serial.print("[");
    Serial.print(RESP_READY);
    Serial.println("]");
    
    digitalWrite(LED_STATUS_PIN, HIGH);
}

// ============================================================
// LOOP
// ============================================================
void loop() {
    // UART komut okuma
    while (Serial.available()) {
        char c = Serial.read();
        
        if (c == '<') {
            // Komut başlangıcı
            cmdIndex = 0;
            cmdReady = false;
        } else if (c == '>') {
            // Komut sonu
            cmdBuffer[cmdIndex] = '\0';
            cmdReady = true;
        } else if (cmdIndex < (int)(sizeof(cmdBuffer) - 1)) {
            cmdBuffer[cmdIndex++] = c;
        }
    }
    
    // Komut işle
    if (cmdReady) {
        processCommand(cmdBuffer);
        cmdReady = false;
        cmdIndex = 0;
    }
    
    // Otomatik tarama
    handleScan();
    
    // Status LED blink (aktif göstergesi)
    static unsigned long lastBlink = 0;
    if (millis() - lastBlink > (scanActive ? 250 : 1000)) {
        lastBlink = millis();
        digitalWrite(LED_STATUS_PIN, !digitalRead(LED_STATUS_PIN));
    }
}
