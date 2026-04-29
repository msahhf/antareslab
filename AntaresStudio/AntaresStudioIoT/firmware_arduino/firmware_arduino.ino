// =====================================================================
// AntaresStudio IoT - Arduino Nano Firmware v4.0.0 (Hybrid Priority)
// =====================================================================
// Optimized for:
// - Connection-aware image routing support
// - 5-minute autonomous counter (Arduino-First priority)
// - "System Busy" rejection for PC commands
// =====================================================================

#include <DHT.h>
#include <avr/wdt.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>

// --- PIN CONFIGURATION ---
#define DHTPIN         10
#define DHTTYPE        DHT22
#define SOIL_PIN       A0
#define FAN_SLY_PIN    11
#define FAN_DZ_PIN     13
#define HEATER_PIN     5
#define STEP_PIN       9
#define DIR_PIN        8
#define ENA_PIN        7
#define HOME_SW_PIN    6
#define LED_PIN        LED_BUILTIN

// --- CONSTANTS ---
const float MOTOR_STEPS_PER_DEG = 4.55;
const int   SCAN_SHOTS          = 8;
const int   SCAN_STEP_DEG       = 45;
const unsigned long TELEMETRY_INTERVAL = 1000;
const unsigned long AUTO_SCAN_INTERVAL = 300000; // 5 Minutes (300,000 ms)

// --- GLOBAL OBJECTS ---
DHT dht(DHTPIN, DHTTYPE);
LiquidCrystal_I2C lcd(0x27, 20, 4);

// --- STATE VARIABLES ---
enum SystemState { IDLE, SCANNING, HOMING, ERROR };
SystemState currentState = IDLE;

struct Telemetry {
  float temp = 0;
  float hum = 0;
  int   soil = 0;
  int   heater = 0;
  bool  fanSly = false;
  bool  fanDz = false;
  bool  isManual = false;
} telem;

// Motor State
long targetPosition = 0;
long currentPosition = 0;
unsigned long lastStepTime = 0;
int stepDelay = 800; // microseconds
bool motorMoving = false;

// Scan State
int currentShot = 0;
unsigned long lastScanActionTime = 0;
unsigned long lastCommandReceivedTime = 0; // For 5-minute counter
enum ScanSubState { WAIT_START, TRIGGER_CAP, WAIT_CAP, MOVE_NEXT } scanSubState = WAIT_START;

// UART Buffer
char rxBuf[64];
int rxIdx = 0;

// ===================== HELPERS =====================

void sendTelemetry() {
  telem.temp = dht.readTemperature();
  telem.hum = dht.readHumidity();
  telem.soil = analogRead(SOIL_PIN);

  Serial.print(F("DATA,"));
  Serial.print(isnan(telem.temp) ? 0.0 : telem.temp, 1);
  Serial.print(F(","));
  Serial.print(isnan(telem.hum) ? 0 : (int)telem.hum);
  Serial.print(F(","));
  Serial.print(telem.soil);
  Serial.print(F(","));
  Serial.print(telem.heater);
  Serial.print(F(","));
  Serial.print(telem.fanSly ? 1 : 0);
  Serial.print(F(","));
  Serial.print(telem.fanDz ? 1 : 0);
  Serial.print(F(","));
  Serial.println(telem.isManual ? F("MANUEL") : F("OTONOM"));
}

void applyOutputs() {
  analogWrite(HEATER_PIN, telem.heater);
  digitalWrite(FAN_SLY_PIN, telem.fanSly ? HIGH : LOW);
  digitalWrite(FAN_DZ_PIN, telem.fanDz ? HIGH : LOW);
}

// ===================== MOTOR CONTROL (NON-BLOCKING) =====================

void updateMotor() {
  if (currentPosition != targetPosition) {
    motorMoving = true;
    unsigned long now = micros();
    if (now - lastStepTime >= stepDelay) {
      digitalWrite(ENA_PIN, LOW); // Enable
      digitalWrite(DIR_PIN, targetPosition > currentPosition ? HIGH : LOW);
      
      digitalWrite(STEP_PIN, HIGH);
      delayMicroseconds(2); // Small pulse
      digitalWrite(STEP_PIN, LOW);
      
      if (targetPosition > currentPosition) currentPosition++;
      else currentPosition--;
      
      lastStepTime = now;
    }
  } else {
    if (motorMoving) {
      motorMoving = false;
    }
  }
}

void moveToAngle(float deg) {
  targetPosition = (long)(deg * MOTOR_STEPS_PER_DEG);
}

// ===================== COMMAND HANDLER =====================

void processCommand(const char* cmd) {
  lastCommandReceivedTime = millis(); // Reset autonomous counter

  if (strcmp(cmd, "PING") == 0) {
    Serial.println(F("PONG"));
    return;
  }

  // Priority Rejection: If system is busy with a scan or homing, reject PC commands
  if (currentState != IDLE && cmd[0] != 'X') {
    Serial.println(F("BUSY"));
    return;
  }

  char type = cmd[0];
  switch (type) {
    case 'R': // Rotate
      if (strlen(cmd) > 2) moveToAngle(atof(cmd + 2));
      Serial.println(F("OK,ROT"));
      break;
    case 'H': // Home
      currentState = HOMING;
      Serial.println(F("OK,HOMING"));
      break;
    case 'G': // Start Scan
      currentState = SCANNING;
      currentShot = 0;
      scanSubState = TRIGGER_CAP;
      Serial.println(F("OK,SCAN_START"));
      break;
    case 'X': // Cancel
      currentState = IDLE;
      Serial.println(F("OK,CANCEL"));
      break;
    case 'P': // Manual Mode
      telem.isManual = true;
      Serial.println(F("OK,MANUAL"));
      break;
    case 'C': // Auto Mode
      telem.isManual = false;
      Serial.println(F("OK,AUTO"));
      break;
    default:
      Serial.println(F("ERR,CMD"));
      break;
  }
}

// ===================== STATE MACHINE =====================

void handleScanning() {
  switch (scanSubState) {
    case TRIGGER_CAP:
      Serial.println(F("CEK")); // ESP32 intercepts this to route image
      lastScanActionTime = millis();
      scanSubState = WAIT_CAP;
      break;
      
    case WAIT_CAP:
      // In v4.0, we wait for "OK,CAP" from ESP32 confirming storage (Direct or SD)
      if (millis() - lastScanActionTime > 10000) { 
        scanSubState = MOVE_NEXT;
      }
      break;
      
    case MOVE_NEXT:
      if (currentShot < SCAN_SHOTS - 1) {
        currentShot++;
        moveToAngle(currentShot * SCAN_STEP_DEG);
        scanSubState = WAIT_START;
      } else {
        currentState = IDLE;
        Serial.println(F("360_END"));
      }
      break;
      
    case WAIT_START:
      if (!motorMoving) {
        scanSubState = TRIGGER_CAP;
      }
      break;
  }
}

void handleHoming() {
  static unsigned long homeTimer = 0;
  if (digitalRead(HOME_SW_PIN) == LOW) {
    currentPosition = 0;
    targetPosition = 0;
    currentState = IDLE;
    return;
  }
  
  if (millis() - homeTimer > 10) {
    targetPosition--;
    homeTimer = millis();
  }
}

// ===================== SETUP & LOOP =====================

void setup() {
  Serial.begin(115200);
  
  dht.begin();
  lcd.init();
  lcd.backlight();
  lcd.print(F("Antares v4.0"));
  
  pinMode(FAN_SLY_PIN, OUTPUT);
  pinMode(FAN_DZ_PIN, OUTPUT);
  pinMode(HEATER_PIN, OUTPUT);
  pinMode(STEP_PIN, OUTPUT);
  pinMode(DIR_PIN, OUTPUT);
  pinMode(ENA_PIN, OUTPUT);
  pinMode(HOME_SW_PIN, INPUT_PULLUP);
  
  digitalWrite(ENA_PIN, HIGH); // Start disabled
  
  lastCommandReceivedTime = millis();
  wdt_enable(WDTO_4S);
}

void loop() {
  wdt_reset();
  
  // 1. UART Bridge
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '<') rxIdx = 0;
    else if (c == '>') {
      rxBuf[rxIdx] = '\0';
      processCommand(rxBuf);
    } else if (rxIdx < 63) {
      rxBuf[rxIdx++] = c;
    }
  }
  
  // 2. Motor Update
  updateMotor();
  
  // 3. State Machine
  if (currentState == SCANNING) handleScanning();
  else if (currentState == HOMING) handleHoming();
  else if (currentState == IDLE) {
    // 5-Minute Autonomous Trigger
    if (millis() - lastCommandReceivedTime >= AUTO_SCAN_INTERVAL) {
      lastCommandReceivedTime = millis();
      currentState = SCANNING;
      currentShot = 0;
      scanSubState = TRIGGER_CAP;
      lcd.setCursor(0, 1);
      lcd.print(F("AUTO SCAN START"));
    }
  }
  
  // 4. Telemetry (Async)
  static unsigned long lastTelem = 0;
  if (millis() - lastTelem >= TELEMETRY_INTERVAL) {
    sendTelemetry();
    applyOutputs();
    lastTelem = millis();
  }
}
