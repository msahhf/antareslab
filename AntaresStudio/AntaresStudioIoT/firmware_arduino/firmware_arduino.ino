// =====================================================================
// AntaresStudio IoT - Arduino Nano Firmware v2.1 (Production Ready)
// =====================================================================
// Değişiklik v2.1:
//   [2a] Homing mekanizması (limit switch + timeout fallback)
//   [2b] SD kart hata raporlama LCD'ye
//   [3]  Otonom çekim sırasında UART komut kuyruğu (race condition)
//   [4]  Watchdog timer (donma koruması)
//   [5]  Geliştirilmiş hata yönetimi
// =====================================================================

#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include "DHT.h"
#include <avr/wdt.h>

// --- PIN TANIMLAMALARI ---
#define DHTPIN       10
#define DHTTYPE      DHT22
#define SOIL_PIN     A0
#define FAN_SLY_PIN  11
#define FAN_DZ_PIN   13
#define HEATER_PIN   5
#define STEP_PIN     9
#define DIR_PIN      8
#define ENA_PIN      7
#define LED_PIN      LED_BUILTIN
#define HOME_SW_PIN  6      // [2a] Limit switch / Hall Effect sensör

// --- MOTOR SABİTLERİ ---
const float motorConstant = 4.55;  // step/derece
const int scanShots = 8;
const int scanStepDeg = 45;
const int HOME_MAX_STEPS = 2000;   // [2a] Homing sırasında max adım (güvenlik limiti)

// --- ZAMANLAYICI ---
const unsigned long autoScanDelayMs = 300000;  // 5 dakika

// --- NESNELER ---
DHT dht(DHTPIN, DHTTYPE);
LiquidCrystal_I2C lcd(0x27, 20, 4);

// Özel ikonlar
byte termometre[8] = {B00100,B01010,B01010,B01110,B01110,B11111,B11111,B01110};
byte nemIkon[8]    = {B00100,B00100,B01010,B01010,B10001,B10001,B10001,B01110};

// --- DURUM DEĞİŞKENLERİ ---
bool studioPaused = false;
bool scanActive = false;
int  scanStep = 0;
int  motorSpeed = 800;           // us
bool fanSlyStatus = false;
bool fanDzStatus = false;
int  heaterPower = 0;
int  setTempA = 24;
int  setTempB = 0;
unsigned long startTime = 0;
unsigned long lastTelemetryTime = 0;
long currentPosition = 0;
bool isHomed = false;

// [3] Otonom çekim kilidi — tarama sırasında komut işlemeyi ertele
volatile bool autoScanBusy = false;

// [2b] ESP32'den gelen SD hata durumu
bool espSDError = false;

// [4] Watchdog: Otonom taramada donma önleme
unsigned long scanWatchdog = 0;
const unsigned long SCAN_WATCHDOG_TIMEOUT = 60000;  // 60sn (8 fotoğraf için max süre)

// UART buffer
char cmdBuffer[64];
int  cmdIndex = 0;
bool cmdReady = false;

// Ertelenmiş komut kuyruğu (max 1 komut)
char deferredCmd[64];
bool hasDeferredCmd = false;

// =========================== YARDIMCILAR ============================

void printLine(int row, const __FlashStringHelper* fsh) {
  lcd.setCursor(0, row);
  String s = String(fsh);
  while (s.length() < 20) s += " ";
  lcd.print(s.substring(0, 20));
}

void printLine(int row, String s) {
  lcd.setCursor(0, row);
  while (s.length() < 20) s += " ";
  lcd.print(s.substring(0, 20));
}

void applyFanOutputs() {
  digitalWrite(FAN_SLY_PIN, fanSlyStatus ? HIGH : LOW);
  digitalWrite(FAN_DZ_PIN,  fanDzStatus  ? HIGH : LOW);
}

void moveSteps(int steps) {
  digitalWrite(ENA_PIN, LOW);
  for (int i = 0; i < steps; i++) {
    digitalWrite(STEP_PIN, HIGH);
    delayMicroseconds(motorSpeed);
    digitalWrite(STEP_PIN, LOW);
    delayMicroseconds(motorSpeed);
    // [4] Uzun hareketlerde watchdog besle
    if (i % 100 == 0) wdt_reset();
  }
  currentPosition += steps;
}

void rotateToAngle(float degrees) {
  long targetSteps = (long)(degrees * motorConstant);
  long delta = targetSteps - currentPosition;
  if (delta == 0) return;
  digitalWrite(DIR_PIN, delta > 0 ? HIGH : LOW);
  moveSteps(abs(delta));
  currentPosition = targetSteps;
}

// [2a] Homing — limit switch ile veya timeout ile
void homeMotor() {
  Serial.println(F("[HOME] Baslatiliyor..."));
  lcd.clear();
  printLine(0, F("MOTOR HOME"));
  printLine(1, F("Switch aranıyor..."));

  digitalWrite(ENA_PIN, LOW);
  digitalWrite(DIR_PIN, LOW);  // Geri yöne dön

  bool switchFound = false;

  // Limit switch'i ara
  for (int i = 0; i < HOME_MAX_STEPS; i++) {
    // Limit switch tetiklendi mi?
    if (digitalRead(HOME_SW_PIN) == LOW) {
      switchFound = true;
      Serial.println(F("[HOME] Switch bulundu!"));
      printLine(1, F("Switch BULUNDU"));
      break;
    }

    digitalWrite(STEP_PIN, HIGH);
    delayMicroseconds(motorSpeed);
    digitalWrite(STEP_PIN, LOW);
    delayMicroseconds(motorSpeed);

    if (i % 100 == 0) wdt_reset();
  }

  if (!switchFound) {
    // Limit switch yoksa veya bulunamadıysa → mevcut pozisyonu sıfır kabul et
    Serial.println(F("[HOME] Switch bulunamadi, fallback: mevcut pozisyon=0"));
    printLine(1, F("Fallback: Pos=0"));
  }

  currentPosition = 0;
  isHomed = true;

  delay(300);
  lcd.clear();
  printLine(1, F(">> MOTOR HOME OK"));
  delay(500);
}

// =========================== TELEMETRY ==============================

void sendTelemetryToESP() {
  float t = dht.readTemperature();
  float h = dht.readHumidity();
  int soil = analogRead(SOIL_PIN);

  Serial.print(F("DATA,"));
  Serial.print(isnan(t) ? 0 : t, 1);  Serial.print(",");
  Serial.print(isnan(h) ? 0 : (int)h); Serial.print(",");
  Serial.print(soil);                   Serial.print(",");
  Serial.print(heaterPower);            Serial.print(",");
  Serial.print(fanSlyStatus ? 1 : 0);  Serial.print(",");
  Serial.print(fanDzStatus ? 1 : 0);   Serial.print(",");
  Serial.print(studioPaused ? F("STUDIO") : F("OTONOM"));
  Serial.print(",");
  Serial.print(currentPosition);
  Serial.print(",");
  Serial.print(isHomed ? 1 : 0);
  Serial.println();
}

// =========================== UART KOMUT İŞLEME =====================

void processCommand(const char* cmd) {
  // [3] Otonom tarama sırasında gelen komutları ertele (P ve X hariç)
  if (autoScanBusy && cmd[0] != 'P' && cmd[0] != 'X' && cmd[0] != '?') {
    // P ve X acil komutlar — hemen işlenir (taramayı durdurur)
    // Diğerleri ertelenir
    strncpy(deferredCmd, cmd, sizeof(deferredCmd) - 1);
    deferredCmd[sizeof(deferredCmd) - 1] = '\0';
    hasDeferredCmd = true;
    Serial.print(F("[UART] Komut ertelendi (tarama aktif): "));
    Serial.println(cmd);
    Serial.println(F("[OK,DEFERRED]"));
    return;
  }

  char cmdType = cmd[0];

  switch (cmdType) {
    case 'S': {  // Durum sorgula
      sendTelemetryToESP();
      Serial.println(F("[OK,STATUS]"));
      break;
    }
    case 'H': {  // Motor Home
      homeMotor();
      Serial.println(F("[OK,HOMED]"));
      break;
    }
    case 'R': {  // Açıya dön: R,90.0
      float angle = 0;
      if (strlen(cmd) > 2) angle = atof(cmd + 2);
      rotateToAngle(angle);
      Serial.print(F("[OK,POS,"));
      Serial.print(angle);
      Serial.println("]");
      break;
    }
    case 'T': {  // Adım sayısı kadar dön: T,200
      int steps = 0;
      if (strlen(cmd) > 2) steps = atoi(cmd + 2);
      digitalWrite(DIR_PIN, HIGH);
      moveSteps(abs(steps));
      Serial.print(F("[OK,STEP,"));
      Serial.print(steps);
      Serial.println("]");
      break;
    }
    case 'E': {  // Motor etkinleştir
      digitalWrite(ENA_PIN, LOW);
      Serial.println(F("[OK,MOT_ON]"));
      break;
    }
    case 'D': {  // Motor devre dışı
      digitalWrite(ENA_PIN, HIGH);
      Serial.println(F("[OK,MOT_OFF]"));
      break;
    }
    case 'V': {  // Hız ayarla: V,800
      if (strlen(cmd) > 2) {
        motorSpeed = atoi(cmd + 2);
        motorSpeed = constrain(motorSpeed, 200, 5000);
      }
      Serial.print(F("[OK,SPD,"));
      Serial.print(motorSpeed);
      Serial.println("]");
      break;
    }
    case 'P': {  // Studio bağlandı - otonom duraklat
      studioPaused = true;
      autoScanBusy = false;  // Tarama kesildi
      scanActive = false;
      lcd.clear();
      printLine(0, F(">>> STUDIO BAGLI <<<"));
      printLine(3, F("Komut Bekleniyor..."));
      Serial.println(F("[OK,PAUSED]"));
      break;
    }
    case 'C': {  // Studio ayrıldı - otonom devam
      studioPaused = false;
      startTime = millis();
      lcd.clear();
      Serial.println(F("[OK,RESUMED]"));
      break;
    }
    case 'G': {  // 360 tarama başlat
      if (!studioPaused) { Serial.println(F("[ERR,NOT_STUDIO]")); break; }
      scanActive = true;
      scanStep = 0;
      Serial.println(F("[OK,SCAN_START]"));
      break;
    }
    case 'X': {  // Tarama durdur (acil)
      autoScanBusy = false;
      scanActive = false;
      scanStep = 0;
      Serial.println(F("[OK,SCAN_STOP]"));
      break;
    }
    case '?': {  // Ping
      Serial.println(F("[OK,PONG]"));
      break;
    }
    default: {
      Serial.println(F("[ERR,UNKNOWN]"));
      break;
    }
  }
}

// =========================== OTONOM MANTIK ==========================

void runAutonomousLogic() {
  if (studioPaused) return;

  static unsigned long lastUpdate = 0;
  if (millis() - lastUpdate < 1000) return;
  lastUpdate = millis();

  float t = dht.readTemperature();
  float h = dht.readHumidity();
  float targetTemp = (float)setTempA + ((float)setTempB / 100.0);

  // --- Adaptif Sıcaklık Kontrolü ---
  if (!isnan(t)) {
    if (t < targetTemp) {
      float fark = targetTemp - t;
      if      (fark >= 3.0) heaterPower = 200;
      else if (fark >= 2.0) heaterPower = 150;
      else if (fark >= 1.0) heaterPower = 100;
      else if (fark >= 0.5) heaterPower = 60;
      else                  heaterPower = 30;
      fanSlyStatus = true;
      fanDzStatus  = false;
    } else if (t > targetTemp) {
      fanSlyStatus = false;
      fanDzStatus  = true;
      heaterPower  = 0;
    } else {
      fanSlyStatus = false;
      fanDzStatus  = false;
      heaterPower  = 0;
    }
  }
  applyFanOutputs();
  analogWrite(HEATER_PIN, heaterPower);

  // --- LCD Güncelleme (Otonom Ekran) ---
  printLine(0, F("MOD: OTONOM"));
  
  if (espSDError) {
    // [2b] SD kart hatası bildirimi
    printLine(1, "T:" + String(t, 1) + " H:%" + String((int)h));
    printLine(2, F("!! SD KART HATA !!"));
  } else {
    printLine(1, "T:" + String(t, 1) + " H:%" + String((int)h) + " Hdf:" + String(targetTemp, 1));
    
    String l2 = "S:" + String(fanSlyStatus ? "ON" : "OF") +
                " D:" + String(fanDzStatus ? "ON" : "OF") +
                " H:" + String(map(heaterPower, 0, 255, 0, 100)) + "%";
    printLine(2, l2);
  }

  // --- Geri Sayım ---
  long kalanSn = (long)((autoScanDelayMs - (millis() - startTime)) / 1000);

  if (kalanSn > 0) {
    int dk = kalanSn / 60;
    int sn = kalanSn % 60;
    String zamanStr = "Sonraki: " + String(dk) + ":";
    if (sn < 10) zamanStr += "0";
    zamanStr += String(sn);
    printLine(3, zamanStr);
  } else {
    // --- 5 Dakika Doldu: Otonom Çekim ---
    start360Capture();
    startTime = millis();
  }
}

void start360Capture() {
  // [3] Kilit: Otonom tarama başladı, normal komutlar ertelenir
  autoScanBusy = true;
  espSDError = false;
  scanWatchdog = millis();

  lcd.clear();
  printLine(0, F("360 TARAMA BASLADI"));
  digitalWrite(ENA_PIN, LOW);
  digitalWrite(DIR_PIN, HIGH);

  Serial.println();
  delay(100);
  Serial.println(F("360_START"));
  delay(1500);

  for (int i = 0; i < scanShots; i++) {
    // [4] Watchdog kontrolü
    wdt_reset();
    if (millis() - scanWatchdog > SCAN_WATCHDOG_TIMEOUT) {
      Serial.println(F("[SCAN] Watchdog zaman asimi!"));
      break;
    }

    // [3] Tarama sırasında acil komut kontrolü (P veya X)
    while (Serial.available()) {
      char c = Serial.read();
      if (c == '<') {
        cmdIndex = 0;
        cmdReady = false;
      } else if (c == '>') {
        cmdBuffer[cmdIndex] = '\0';
        // Sadece P ve X hemen işlenir
        if (cmdBuffer[0] == 'P' || cmdBuffer[0] == 'X') {
          processCommand(cmdBuffer);
          if (!autoScanBusy) {
            // Tarama iptal edildi
            Serial.println(F("360_END"));
            return;
          }
        } else {
          // Diğer komutları ertele
          strncpy(deferredCmd, cmdBuffer, sizeof(deferredCmd) - 1);
          deferredCmd[sizeof(deferredCmd) - 1] = '\0';
          hasDeferredCmd = true;
          Serial.println(F("[OK,DEFERRED]"));
        }
        cmdIndex = 0;
      } else if (cmdIndex < (int)(sizeof(cmdBuffer) - 1)) {
        cmdBuffer[cmdIndex++] = c;
      }
    }

    Serial.println(F("CEK"));
    printLine(1, "FOTO: " + String(i + 1) + "/" + String(scanShots));

    // ESP32'nin çekim + SD kayıt süresi bekle (yanıt bekleme)
    unsigned long cekStart = millis();
    bool cekOK = false;
    while (millis() - cekStart < 10000) {  // Max 10sn bekle
      if (Serial.available()) {
        String resp = Serial.readStringUntil('\n');
        resp.trim();
        if (resp == "OK") { cekOK = true; break; }
        if (resp == "FAIL") { break; }
        // [2b] SD hata bildirimi
        if (resp == "SD_ERR") {
          espSDError = true;
          printLine(2, F("!! SD HATA !!"));
          break;
        }
      }
      wdt_reset();
      delay(10);
    }

    if (!cekOK && !espSDError) {
      printLine(2, "FOTO " + String(i + 1) + " BASARISIZ");
    }

    // Motor döndür
    moveSteps(round(scanStepDeg * motorConstant));
    delay(500);
  }

  Serial.println(F("360_END"));
  printLine(1, F("TARAMA TAMAM"));
  delay(1500);
  lcd.clear();

  // [3] Kilit kaldır
  autoScanBusy = false;
}

// =========================== SETUP ==================================

void setup() {
  Serial.begin(115200);
  lcd.init();
  lcd.backlight();
  dht.begin();
  lcd.createChar(1, termometre);
  lcd.createChar(2, nemIkon);

  pinMode(FAN_SLY_PIN, OUTPUT);
  pinMode(FAN_DZ_PIN, OUTPUT);
  pinMode(HEATER_PIN, OUTPUT);
  pinMode(STEP_PIN, OUTPUT);
  pinMode(DIR_PIN, OUTPUT);
  pinMode(ENA_PIN, OUTPUT);
  pinMode(LED_PIN, OUTPUT);
  pinMode(HOME_SW_PIN, INPUT_PULLUP);  // [2a] Limit switch (aktif LOW)

  digitalWrite(ENA_PIN, LOW);
  analogWrite(HEATER_PIN, 0);

  // Giriş ekranı
  lcd.clear();
  lcd.setCursor(2, 1);
  lcd.print(F("ANTARES STUDIO"));
  lcd.setCursor(3, 2);
  lcd.print(F("IoT v2.1 PROD"));
  delay(1500);
  lcd.clear();

  startTime = millis();

  // [4] Watchdog timer başlat (8 saniye)
  wdt_enable(WDTO_8S);

  Serial.println(F("[RDY]"));
  digitalWrite(LED_PIN, HIGH);
}

// =========================== LOOP ===================================

void loop() {
  // [4] Watchdog besle
  wdt_reset();

  // --- UART Komut Okuma ---
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '<') {
      cmdIndex = 0;
      cmdReady = false;
    } else if (c == '>') {
      cmdBuffer[cmdIndex] = '\0';
      cmdReady = true;
    } else if (cmdIndex < (int)(sizeof(cmdBuffer) - 1)) {
      cmdBuffer[cmdIndex++] = c;
    }
  }

  if (cmdReady) {
    processCommand(cmdBuffer);
    cmdReady = false;
    cmdIndex = 0;
  }

  // [3] Ertelenmiş komutu işle (tarama bittikten sonra)
  if (hasDeferredCmd && !autoScanBusy) {
    processCommand(deferredCmd);
    hasDeferredCmd = false;
  }

  // --- Otonom Mantık ---
  runAutonomousLogic();

  // --- Studio Bağlı İken LCD ---
  if (studioPaused && !scanActive) {
    static unsigned long lastStudioUpdate = 0;
    if (millis() - lastStudioUpdate > 1000) {
      lastStudioUpdate = millis();
      float t = dht.readTemperature();
      float h = dht.readHumidity();
      printLine(0, F(">>> STUDIO BAGLI <<<"));
      printLine(1, "T:" + String(t, 1) + " H:%" + String((int)h));
      printLine(2, "Motor Pos: " + String(currentPosition));
      printLine(3, F("Komut Bekleniyor..."));
    }
  }

  // --- Telemetri (2 saniyede bir) ---
  if (millis() - lastTelemetryTime > 2000) {
    sendTelemetryToESP();
    lastTelemetryTime = millis();
  }

  // --- LED Blink (Hayat Göstergesi) ---
  static unsigned long lastBlink = 0;
  unsigned long blinkInterval = studioPaused ? 250 : (autoScanBusy ? 100 : 1000);
  if (millis() - lastBlink > blinkInterval) {
    lastBlink = millis();
    digitalWrite(LED_PIN, !digitalRead(LED_PIN));
  }
}
