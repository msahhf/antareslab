#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include "DHT.h"
#include <avr/wdt.h>
#include <avr/pgmspace.h>

// --- PIN TANIMLAMALARI ---
#define DHTPIN 10
#define DHTTYPE DHT22
#define SOIL_PIN A0
#define FAN_SLY_PIN 11
#define FAN_DZ_PIN 13
#define HEATER_PIN 5
#define STEP_PIN 9
#define DIR_PIN 8
#define ENA_PIN 7

const int btnLeft = 2, btnRight = 3, btnSelect = 4, btnRow = 6;
DHT dht(DHTPIN, DHTTYPE);
LiquidCrystal_I2C lcd(0x27, 20, 4);

// Özel İkonlar
byte termometre[8] = { B00100, B01010, B01010, B01110, B01110, B11111, B11111, B01110 };
byte nemIkon[8] = { B00100, B00100, B01010, B01010, B10001, B10001, B10001, B01110 };

// --- YATAY KART MENÜ (PROGMEM) ---
const char p0[] PROGMEM = "Sicaklik & Nem";
const char p1[] PROGMEM = "Toprak Nem";
const char p2[] PROGMEM = "Isitici";
const char p3[] PROGMEM = "Fanlar";
const char p4[] PROGMEM = "Motor Unitesi";
const char p5[] PROGMEM = "Kamera";
const char p6[] PROGMEM = "Oto Cekim";
const char p7[] PROGMEM = "Ayarlar";
const char* const pageNames[] PROGMEM = { p0, p1, p2, p3, p4, p5, p6, p7 };
const int totalPages = 8;
int currentPage = 0;

// Durum Değişkenleri
bool inMenuMode = false;
bool inSubMenu = false;
bool settingsInfoMode = false;
bool fanSlyStatus = false;
bool fanDzStatus = false;
int motorSpeed = 800;
int heaterPower = 0;
int targetAngle = 90;
int angles[] = { 15, 30, 45, 60, 75, 90, 180 };
int angleIndex = 0;
bool isAutonomous = true;
unsigned long startTime = 0;
bool autoScanDone = false;

const float motorConstant = 4.55;
const int scanShots = 8;
const int scanStepDeg = 45;

// --- SÜRE: 5 DAKİKA ---
const unsigned long autoScanDelayMs = 300000;

unsigned long lastTelemetryTime = 0;

// --- Hedef Sıcaklık Değişkenleri ---
int setTempA = 24;  // Tam sayı
int setTempB = 0;   // Küsürat

// -------------------------- YARDIMCILAR ----------------------------

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

String progressBar10(int percent) {
  percent = constrain(percent, 0, 100);
  int filled = (percent + 9) / 10;
  String bar = "[";
  for (int i = 0; i < 10; i++) bar += (i < filled ? "X" : "-");
  bar += "]";
  return bar;
}

void applyFanOutputs() {
  digitalWrite(FAN_SLY_PIN, fanSlyStatus ? HIGH : LOW);
  digitalWrite(FAN_DZ_PIN, fanDzStatus ? HIGH : LOW);
}

bool pressed(int pin) {
  static unsigned long lastTime[14];
  static bool lastState[14];
  bool now = (digitalRead(pin) == LOW);
  bool was = lastState[pin];
  lastState[pin] = now;
  if (now && !was && millis() - lastTime[pin] > 180) {
    lastTime[pin] = millis();
    return true;
  }
  return false;
}

void rebootBoard() {
  lcd.clear();
  printLine(1, F("Sistem Yeniden..."));
  printLine(2, F("Baslatiliyor"));
  delay(600);
  wdt_enable(WDTO_15MS);
  while (1) {}
}

bool checkGlobalRebootHotkey() {
  static unsigned long lastTap = 0;
  static bool armed = false;
  if (pressed(btnRow)) {
    unsigned long now = millis();
    if (!armed) {
      armed = true;
      lastTap = now;
    } else {
      if (now - lastTap < 450) {
        armed = false;
        return true;
      }
      lastTap = now;
    }
  }
  if (armed && millis() - lastTap > 500) armed = false;
  return false;
}

bool checkRowLongPressToggle() {
  static bool wasDown = false;
  static unsigned long downAt = 0;
  static bool fired = false;
  bool down = (digitalRead(btnRow) == LOW);
  if (down && !wasDown) {
    wasDown = true;
    downAt = millis();
    fired = false;
  }
  if (!down && wasDown) {
    wasDown = false;
    fired = false;
  }
  if (down && !fired && (millis() - downAt >= 2000)) {
    fired = true;
    return true;
  }
  return false;
}

void moveSteps(int steps) {
  for (int i = 0; i < steps; i++) {
    digitalWrite(STEP_PIN, HIGH);
    delayMicroseconds(motorSpeed);
    digitalWrite(STEP_PIN, LOW);
    delayMicroseconds(motorSpeed);
  }
}

// -------------------------- HEDEF SICAKLIK AYAR MENÜSÜ -----------------
void editTargetTemp() {
  while (digitalRead(btnSelect) == LOW)
    ;  // Tuşun bırakılmasını bekle
  delay(100);

  lcd.clear();
  int step = 1;

  while (true) {
    if (step == 1) {  // Adım 1: Tam Sayı
      printLine(0, F("ADIM 1: TAM SAYI"));
      printLine(1, "Deger: >" + String(setTempA) + "<." + (setTempB < 10 ? "0" : "") + String(setTempB));
      printLine(2, F("Min: 20 Derece"));
      printLine(3, F("<-AZALT   [OK]   ART+>"));

      if (pressed(btnLeft)) {
        if (setTempA > 20) setTempA--;
      }
      if (pressed(btnRight)) {
        if (setTempA < 40) setTempA++;
      }
      if (pressed(btnSelect)) {
        step = 2;
        lcd.clear();
        delay(200);
      }
    } else if (step == 2) {  // Adım 2: Küsürat
      printLine(0, F("ADIM 2: KUSURAT"));
      printLine(1, "Deger: " + String(setTempA) + ".>" + (setTempB < 10 ? "0" : "") + String(setTempB) + "<");
      printLine(2, F("Adim: 0.05 C"));
      printLine(3, F("<-AZALT   [OK]   ART+>"));

      if (pressed(btnLeft)) {
        setTempB -= 5;
        if (setTempB < 0) setTempB = 95;
      }
      if (pressed(btnRight)) {
        setTempB += 5;
        if (setTempB > 95) setTempB = 0;
      }
      if (pressed(btnSelect)) {
        lcd.clear();
        printLine(1, F("AYAR KAYDEDILDI!"));
        delay(1000);
        lcd.clear();
        return;
      }
    }
  }
}

// ---------------------------- EKRANLAR -----------------------------

void showIntro() {
  lcd.clear();
  lcd.setCursor(3, 1);
  lcd.print(F("AKILLI KAPSUL"));
  lcd.setCursor(2, 2);
  lcd.print(F("Arayuz V8-LAB"));
  delay(1500);
  lcd.clear();
}

void selectMode() {
  lcd.clear();
  printLine(0, F("== Mod Seciniz =="));
  printLine(1, F("< Otonom   > Manuel"));
  printLine(2, F("[HOME] (2sn): Deg."));
  printLine(3, F("Secim Bekleniyor..."));
  while (true) {
    if (checkGlobalRebootHotkey()) rebootBoard();
    if (pressed(btnLeft)) {
      isAutonomous = true;
      break;
    }
    if (pressed(btnRight)) {
      isAutonomous = false;
      break;
    }
  }
  lcd.clear();
  printLine(1, isAutonomous ? F("V Otonom Mod Aktif") : F("V Manuel Mod Aktif"));
  delay(900);
  lcd.clear();
}

void showDashboard() {
  static unsigned long lastUpdate = 0;
  if (millis() - lastUpdate > 1000) {
    float t = dht.readTemperature();
    float h = dht.readHumidity();
    printLine(0, F("== Sistem Ozeti =="));
    String l1 = String((char)1) + " Sicaklik: " + (isnan(t) ? "!" : String(t, 1) + " C");
    printLine(1, l1);
    String l2 = String((char)2) + " Nem: %" + (isnan(h) ? "!" : String((int)h));
    printLine(2, l2);
    String l3 = "S:" + String(fanSlyStatus ? "ON" : "OF") + " D:" + String(fanDzStatus ? "ON" : "OF") + " H:" + String(map(heaterPower, 0, 255, 0, 100)) + "%";
    printLine(3, l3);
    lastUpdate = millis();
  }
}

// -------------------------- MANUEL MENÜ ----------------------------

void drawMenuCard() {
  char buffer[21];
  strcpy_P(buffer, (char*)pgm_read_word(&(pageNames[currentPage])));
  String line0 = "[" + String(currentPage + 1) + "/" + String(totalPages) + "] ";
  printLine(0, line0 + String(buffer));
  printLine(1, F("--------------------"));
  lcd.setCursor(0, 2);
  lcd.print(F("> [OK] icin bas"));
  printLine(3, F("< Sol   [OK]   Sag >"));
}

void openSubMenu() {
  while (inSubMenu) {
    if (checkGlobalRebootHotkey()) rebootBoard();
    if (checkRowLongPressToggle()) {
      isAutonomous = !isAutonomous;
      lcd.clear();
      printLine(1, isAutonomous ? F("V Otonom Mod Aktif") : F("V Manuel Mod Aktif"));
      delay(900);
      inSubMenu = false;
      inMenuMode = false;
      return;
    }

    char titleBuf[21];
    strcpy_P(titleBuf, (char*)pgm_read_word(&(pageNames[currentPage])));
    printLine(0, "AYAR: " + String(titleBuf));

    if (currentPage == 0) {  // SICAKLIK & NEM
      float t = dht.readTemperature();
      float h = dht.readHumidity();
      printLine(1, F("DHT22 Sensor"));
      printLine(2, "Sic:" + String(t, 1) + "C  Nem:%" + String((int)h));
      printLine(3, F("[OK]=Geri"));
    } else if (currentPage == 1) {  // TOPRAK NEM
      int soilVal = analogRead(SOIL_PIN);
      printLine(1, "Toprak ADC: " + String(soilVal));
      printLine(2, "Durum: " + String(soilVal < 500 ? "ISLAK" : "KURU"));
      printLine(3, F("[OK]=Geri"));
    } else if (currentPage == 2) {  // ISITICI
      int pct = map(heaterPower, 0, 255, 0, 100);
      printLine(1, "Guc: %" + String(pct));
      printLine(2, progressBar10(pct));
      printLine(3, F("<-15  >+15 [OK]=CIK"));
      if (pressed(btnLeft)) {
        heaterPower = max(0, heaterPower - 38);
        analogWrite(HEATER_PIN, heaterPower);
      }
      if (pressed(btnRight)) {
        heaterPower = min(255, heaterPower + 38);
        analogWrite(HEATER_PIN, heaterPower);
      }
    } else if (currentPage == 3) {  // FANLAR
      printLine(1, "SLY.FAN: " + String(fanSlyStatus ? "ON" : "OFF"));
      printLine(2, "DZ.FAN : " + String(fanDzStatus ? "ON" : "OFF"));
      printLine(3, F("< SLY  > DZ [OK]=Cik"));
      if (pressed(btnLeft)) {
        fanSlyStatus = !fanSlyStatus;
        applyFanOutputs();
      }
      if (pressed(btnRight)) {
        fanDzStatus = !fanDzStatus;
        applyFanOutputs();
      }
    } else if (currentPage == 4) {  // MOTOR UNITESI
      targetAngle = angles[angleIndex];
      printLine(1, "Secili: " + String(targetAngle) + " deg");
      printLine(2, F("< DON  > ACI+"));
      printLine(3, F("> ACI+  [OK] Geri"));
      if (pressed(btnRight)) angleIndex = (angleIndex + 1) % 7;
      if (pressed(btnLeft)) {
        printLine(1, ">> " + String(targetAngle) + " DEG...");
        digitalWrite(ENA_PIN, LOW);
        digitalWrite(DIR_PIN, HIGH);
        delay(5);
        moveSteps(round(targetAngle * motorConstant));
        printLine(1, F(">> TAMAMLANDI"));
        delay(1000);
      }
    } else if (currentPage == 5) {  // KAMERA
      printLine(1, F("< FOTO CEK"));
      printLine(3, F("[OK]=Geri [HOME]=Ev"));
      if (pressed(btnLeft)) {
        printLine(2, F("Durum: CEKILIYOR"));
        Serial.println(F("CEK"));
        delay(2000);
        printLine(2, F("Durum: TAMAM"));
        delay(1000);
      }
    } else if (currentPage == 6) {  // OTO CEKIM
      printLine(1, F("ADET: 8 | ACI: 45"));
      printLine(3, F("< BASLAT  [OK]=Geri"));
      if (pressed(btnLeft)) {
        for (int i = 1; i <= 8; i++) {
          printLine(2, "CEKIM: " + String(i) + "/8...");
          Serial.println(F("CEK"));
          delay(3000);
          moveSteps(round(45 * motorConstant));
        }
        printLine(2, F("ISLEM TAMAM!"));
        delay(1500);
      }
    } else if (currentPage == 7) {  // AYARLAR
      if (pressed(btnRight)) settingsInfoMode = !settingsInfoMode;
      if (pressed(btnLeft)) rebootBoard();
      if (!settingsInfoMode) {
        printLine(1, F("SISTEM AYARLARI"));
        printLine(2, F("< REBOOT  > INFO"));
      } else {
        printLine(1, F("SMART CAPSULE V8-LAB"));
        printLine(2, F("UNO R3 & ESP32 CAM"));
        printLine(3, F("GHV MSFL PROJECT"));
      }
    }

    if (pressed(btnSelect)) {
      inSubMenu = false;
      settingsInfoMode = false;
    }
  }
}

void handleHorizontalNavigation() {
  static int lastPage = -1;
  if (lastPage != currentPage) {
    lcd.clear();
    drawMenuCard();
    lastPage = currentPage;
  }
  if (pressed(btnRight)) currentPage = (currentPage + 1) % totalPages;
  if (pressed(btnLeft)) currentPage = (currentPage - 1 + totalPages) % totalPages;
  if (pressed(btnSelect)) {
    inSubMenu = true;
    lcd.clear();
    openSubMenu();
    lcd.clear();
    lastPage = -1;
  }
  if (pressed(btnRow)) {
    inMenuMode = false;
    lcd.clear();
    lastPage = -1;
  }
}

// -------------------------- OTONOM LOGIC ---------------------------

void start360Capture() {
  lcd.clear();
  printLine(0, F("360 TARAMA BASLADI"));
  digitalWrite(ENA_PIN, LOW);
  digitalWrite(DIR_PIN, HIGH);

  // Seri portu temizlemek için boş satır
  Serial.println();
  delay(100);

  // 360 tarama başlangıcını bildir
  Serial.println(F("360_START"));

  // ESP32'nin SD kart işlemleri için zaman tanı
  delay(1500);

  for (int i = 0; i < scanShots; i++) {
    Serial.println(F("CEK"));
    printLine(1, "FOTO: " + String(i + 1) + "/" + String(scanShots));

    // Fotoğrafın SD karta yazılması için ESP32'ye süre ver
    delay(4000);

    moveSteps(round(scanStepDeg * motorConstant));
    delay(500);
  }

  // 360 tarama bitişini bildir
  Serial.println(F("360_END"));

  printLine(1, F("TARAMA TAMAM"));
  delay(1500);
  lcd.clear();
}

void runAutonomousLogic() {
  // OK TUŞU UZUN BASMA (2SN) -> AYAR MENÜSÜ
  static unsigned long selectDownStart = 0;
  if (digitalRead(btnSelect) == LOW) {
    if (selectDownStart == 0) selectDownStart = millis();
    if (millis() - selectDownStart > 2000) {
      unsigned long menuEnterTime = millis();
      editTargetTemp();
      startTime += (millis() - menuEnterTime);  // Süreyi ötele
      selectDownStart = 0;
      return;
    }
  } else {
    selectDownStart = 0;
  }

  static unsigned long lastUpdate = 0;
  if (millis() - lastUpdate >= 1000) {
    float t = dht.readTemperature();
    float targetTemp = (float)setTempA + ((float)setTempB / 100.0);

    // OTONOM SICAKLIK KONTROLÜ
    if (!isnan(t)) {
      if (t < targetTemp) {
        // Mevcut sıcaklık hedeften düşükse -> Salyangoz fan + Adaptif Isıtıcı
        float fark = targetTemp - t;

        if (fark >= 3.0) {
          heaterPower = 200;  // 3°C veya daha fazla fark -> Maksimum güç
        } else if (fark >= 2.0) {  
          heaterPower = 150;  // 2-3°C arası -> Yüksek güç
        } else if (fark >= 1.0) {
          heaterPower = 100;  // 1-2°C arası -> Orta güç
        } else if (fark >= 0.5) {
          heaterPower = 60;  // 0.5-1°C arası -> Düşük güç
        } else {
          heaterPower = 30;  // 0.5°C'den az -> Minimal güç
        }

        fanSlyStatus = true;
        fanDzStatus = false;

      } else if (t > targetTemp) {
        // Mevcut sıcaklık hedeften yüksekse -> Sadece düz fan
        fanSlyStatus = false;
        fanDzStatus = true;
        heaterPower = 0;
      } else {
        // Tam eşitse tüm sistemleri kapat
        fanSlyStatus = false;
        fanDzStatus = false;
        heaterPower = 0;
      }
    }

    applyFanOutputs();
    analogWrite(HEATER_PIN, heaterPower);

    printLine(0, F("MOD: OTONOM (DONGU)"));
    printLine(1, "T:" + String(t, 1) + " Hdf:" + String(targetTemp, 2));

    // --- SÜRE HESAPLAMA ---
    long toplamSaniye = (long)((autoScanDelayMs - (millis() - startTime)) / 1000);

    if (toplamSaniye > 0) {
      // --- Bekleme Modu ---
      int dk = toplamSaniye / 60;
      int sn = toplamSaniye % 60;

      String zamanStr = "Sonraki: " + String(dk) + ":";
      if (sn < 10) zamanStr += "0";
      zamanStr += String(sn);

      printLine(2, zamanStr);
      printLine(3, F("[OK] 2sn > HEDEF ISI"));

    } else {
      // --- SÜRE BİTTİ: ONAY EKRANI ---

      lcd.clear();
      printLine(0, F("OTOMATIK TARAMA?"));
      printLine(2, F("IPTAL -> SAG TUS"));  // İptal için sağ tuş

      bool iptalEdildi = false;

      // 10 Saniyelik Geri Sayım Döngüsü
      for (int i = 10; i > 0; i--) {
        printLine(1, "Basliyor: " + String(i) + " sn");

        // Buton kontrolü için 1 saniyeyi küçük parçalara bölüyoruz
        for (int k = 0; k < 20; k++) {  // 50ms x 20 = 1000ms
          if (pressed(btnRight)) {
            iptalEdildi = true;
            break;  // İç döngüden çık
          }
          delay(50);
        }

        if (iptalEdildi) break;  // Ana geri sayım döngüsünden çık
      }

      if (iptalEdildi) {
        // Kullanıcı iptal ettiyse
        printLine(1, F("!!! IPTAL EDILDI !!!"));
        delay(2000);  // Mesajı okuması için bekle
        lcd.clear();
      } else {
        // İptal edilmediyse taramayı başlat
        start360Capture();
      }

      // Her iki durumda da süreyi sıfırla (İptal edilse de, yapılsa da 10dk sayacı başa döner)
      startTime = millis();
    }
    // ------------------------------------------

    lastUpdate = millis();
  }
}

void sendTelemetryToESP() {
  // Format: DATA,Sicaklik,Nem,Toprak,Isitici,FanSly,FanDz,Mod
  float t = dht.readTemperature();
  float h = dht.readHumidity();
  int soil = analogRead(SOIL_PIN);  // 0-1023

  Serial.print("DATA,");
  Serial.print(isnan(t) ? 0 : t, 1);
  Serial.print(",");
  Serial.print(isnan(h) ? 0 : (int)h);
  Serial.print(",");
  Serial.print(soil);
  Serial.print(",");
  Serial.print(heaterPower);
  Serial.print(",");  // 0-255
  Serial.print(fanSlyStatus ? 1 : 0);
  Serial.print(",");
  Serial.print(fanDzStatus ? 1 : 0);
  Serial.print(",");
  Serial.print(isAutonomous ? "OTONOM" : "MANUEL");
  Serial.println();  // Satır sonu
}

void setup() {
  Serial.begin(115200);
  lcd.init();
  lcd.backlight();
  dht.begin();
  lcd.createChar(1, termometre);
  lcd.createChar(2, nemIkon);
  pinMode(btnLeft, INPUT_PULLUP);
  pinMode(btnRight, INPUT_PULLUP);
  pinMode(btnSelect, INPUT_PULLUP);
  pinMode(btnRow, INPUT_PULLUP);
  pinMode(FAN_SLY_PIN, OUTPUT);
  pinMode(FAN_DZ_PIN, OUTPUT);
  pinMode(HEATER_PIN, OUTPUT);
  pinMode(STEP_PIN, OUTPUT);
  pinMode(DIR_PIN, OUTPUT);
  pinMode(ENA_PIN, OUTPUT);
  digitalWrite(ENA_PIN, LOW);
  analogWrite(HEATER_PIN, 0);
  showIntro();
  selectMode();
  startTime = millis();
}

void loop() {
  if (checkRowLongPressToggle()) {
    isAutonomous = !isAutonomous;
    lcd.clear();
    printLine(1, isAutonomous ? F("V Otonom Mod Aktif") : F("V Manuel Mod Aktif"));
    delay(900);
    lcd.clear();
    if (isAutonomous) {
      startTime = millis();
      autoScanDone = false;
      inMenuMode = inSubMenu = false;
    }
  }
  if (checkGlobalRebootHotkey()) rebootBoard();

  if (isAutonomous) runAutonomousLogic();
  else {
    if (!inMenuMode) {
      showDashboard();
      if (pressed(btnSelect)) {
        inMenuMode = true;
        lcd.clear();
      }
    } else handleHorizontalNavigation();
  }

  if (millis() - lastTelemetryTime > 2000) {
    sendTelemetryToESP();
    lastTelemetryTime = millis();
  }
}