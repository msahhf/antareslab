# Hardware Interface Specification

## ESP32-CAM (AI-Thinker Module)

### Pin Assignment

| Function | GPIO | Notes |
|----------|------|-------|
| **Camera Interface** | | |
| D0 | 5 | Y2 |
| D1 | 18 | Y3 |
| D2 | 19 | Y4 |
| D3 | 21 | Y5 |
| D4 | 36 | Y6 |
| D5 | 39 | Y7 |
| D6 | 34 | Y8 |
| D7 | 35 | Y9 |
| VSYNC | 25 | |
| HREF | 23 | |
| PCLK | 22 | |
| XCLK | 0 | 20 MHz |
| SIOD (SDA) | 26 | SCCB |
| SIOC (SCL) | 27 | SCCB |
| PWDN | 32 | Power down |
| RESET | -1 | Not connected |
| **SD Card (SDMMC 1-bit)** | | |
| D0 | 2 | Data line |
| CLK | 14 | Clock |
| CMD | 15 | Command |
| **UART2 (Arduino Link)** | | |
| TX | 13 | → Arduino RX (D0) |
| RX | 12 | ← Arduino TX (D1) |
| **Arduino Reset** | | |
| RESET | 4 | → Arduino RESET pin |
| **Built-in LED** | 33 | Flash LED |
| **Power** | | |
| VCC | 5V/3.3V | Via regulator |
| GND | GND | Common ground |

### Electrical Characteristics

| Parameter | Value |
|-----------|-------|
| Operating Voltage | 3.3V (regulated from 5V) |
| Current (active) | ~180-250 mA |
| Current (flash) | +100 mA peak |
| WiFi TX Power | 20 dBm max |
| Logic Level | 3.3V (5V tolerant inputs) |

### Camera Specifications

| Parameter | Value |
|-----------|-------|
| Sensor | OV2640 |
| Max Resolution | 1600×1200 (UXGA) |
| Format | JPEG |
| Frame Rates | VGA: 30 fps, UXGA: 15 fps |
| Lens | 2.1mm, FOV ~65° |

---

## Arduino Nano (ATmega328P)

### Pin Assignment

| Function | Pin | Arduino Pin | Notes |
|----------|-----|-------------|-------|
| **UART (ESP32 Link)** | | | |
| RX | D0 | RX | ← ESP32 TX (GPIO 13) |
| TX | D1 | TX | → ESP32 RX (GPIO 12) |
| **Sensors** | | | |
| DHT22 | D10 | Digital | Temp/Humidity |
| Soil Moisture | A0 | Analog | 0-1023 |
| **Actuators** | | | |
| SLY Fan | D11 | Digital/PWM | Salyangoz |
| DZ Fan | D13 | Digital | Düz fan |
| Heater | D5 | PWM | Ceramic heater |
| **Stepper Motor** | | | |
| STEP | D9 | Digital | Step pulse |
| DIR | D8 | Digital | Direction |
| ENA | D7 | Digital | Enable (active LOW) |
| **Homing** | | | |
| Home Switch | D6 | Digital (INPUT_PULLUP) | Hall effect / Limit |
| **Display** | | | |
| LCD I2C | A4 (SDA), A5 (SCL) | 0x27 | 20×4 |
| **Communication** | | | |
| ESP32 RESET | RESET | — | From ESP32 GPIO 4 |
| **Power** | | | |
| VIN | 7-12V | External supply |
| 5V | 5V | USB/Regulated |
| GND | GND | Common |

### Electrical Characteristics

| Parameter | Value |
|-----------|-------|
| MCU | ATmega328P |
| Clock | 16 MHz |
| Flash | 32 KB |
| SRAM | 2 KB |
| EEPROM | 1 KB |
| Operating Voltage | 5V |
| Input Voltage | 7-12V (VIN), 5V (USB) |
| DC Current per I/O | 40 mA |
| ADC Resolution | 10-bit (0-1023) |

---

## Stepper Motor & Driver

### Motor Specifications

| Parameter | Value |
|-----------|-------|
| Type | NEMA 17 (or compatible) |
| Step Angle | 1.8° (200 steps/rev) |
| Driver | DRV8825 / TMC2209 / A4988 |
| Microstepping | 1/16 (configurable) |
| Current | 1.5-2.0 A (per phase) |

### Steps per Degree Calculation

```
Motor steps/rev = 200
Microstepping = 16
Total steps/rev = 200 × 16 = 3200
Steps/degree = 3200 / 360 = 8.89
```

**Firmware constant:** `MOTOR_STEPS_PER_DEG = 4.55` (adjusted for gear ratio if present)

### Wiring (DRV8825 Example)

| Driver Pin | Arduino | Notes |
|------------|---------|-------|
| STEP | D9 | Step pulse |
| DIR | D8 | Direction |
| ENABLE | D7 | Active LOW |
| MS1, MS2, MS3 | GND/VDD | Microstep config |
| VMOT | 12-24V | Motor supply |
| GND | GND | Common |

---

## Climate Control Subsystem

### DHT22 (Temperature/Humidity)

| Pin | Connection |
|-----|------------|
| VCC | 3.3V/5V |
| DATA | D10 |
| GND | GND |
| (NC) | — |

| Spec | Value |
|------|-------|
| Temp Range | -40 to 80°C |
| Humidity Range | 0-100% RH |
| Accuracy | ±0.5°C, ±2% RH |
| Sampling | 1 Hz max |

### Heater (Ceramic, PWM)

| Parameter | Value |
|-----------|-------|
| Type | PTC Ceramic / Resistive |
| Voltage | 12-24V |
| Control | PWM (D5, 0-255) |
| Max Power | ~50-100W |
| Safety | Thermal fuse recommended |

### Fans (Dual)

| Fan | Pin | Type | Control |
|-----|-----|------|---------|
| SLY (Salyangoz) | D11 | 12V DC | Digital ON/OFF |
| DZ (Düz) | D13 | 12V DC | Digital ON/OFF |

---

## LCD Display (I2C 20×4)

| Parameter | Value |
|-----------|-------|
| Controller | HD44780 / PCF8574 |
| Address | 0x27 (default) |
| Columns | 20 |
| Rows | 4 |
| Backlight | Yes |
| SDA | A4 |
| SCL | A5 |

### Display Layout (Autonomous Mode)

```
Line 0: MOD: OTONOM
Line 1: T:25.3 H:60% Hdf:24.0
Line 2: S:ON D:OF H:78%
Line 3: Sonraki: 4:32
```

### Display Layout (Studio Connected)

```
Line 0: >>> STUDIO BAGLI <<<
Line 1: T:25.3 H:60%
Line 2: Motor Pos: 450
Line 3: Komut Bekleniyor...
```

---

## Power Supply Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    12-24V DC Input                       │
└──────────────────────┬──────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
   ┌─────────┐    ┌─────────┐    ┌─────────┐
   │ Stepper │    │ Heater  │    │  Fans   │
   │ Driver  │    │ (PWM)   │    │ (12V)   │
   └─────────┘    └─────────┘    └─────────┘
        │              │              │
        └──────────────┼──────────────┘
                       ▼
              ┌─────────────────┐
              │  5V Regulator   │
              │  (Arduino VIN)  │
              └────────┬────────┘
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
   ┌─────────┐    ┌─────────┐    ┌─────────┐
   │ ESP32   │    │ Arduino │    │ Sensors │
   │ (3.3V)  │    │ (5V)    │    │ (3.3/5V)│
   └─────────┘    └─────────┘    └─────────┘
```

### Power Budget (Estimated)

| Component | Voltage | Current | Power |
|-----------|---------|---------|-------|
| Stepper Motor | 24V | 1.5 A | 36 W |
| Heater | 24V | 3 A | 72 W |
| Fans (2×) | 12V | 0.5 A | 6 W |
| ESP32-CAM | 3.3V | 0.25 A | 0.8 W |
| Arduino Nano | 5V | 0.05 A | 0.25 W |
| Sensors/LCD | 5V | 0.1 A | 0.5 W |
| **Total (max)** | | | **~115 W** |

**Recommendation:** 12-24V / 10A+ supply (240W+ headroom)

---

## Mechanical Interface

### Rotation Platform

| Parameter | Value |
|-----------|-------|
| Rotation | 360° continuous |
| Steps per scan | 8 shots × 45° |
| Position accuracy | ±0.5° (microstepping) |
| Homing | Hall effect sensor (D6) |

### Camera Mount

| Parameter | Value |
|-----------|-------|
| Mount | Fixed on rotation platform |
| Height | Adjustable (Z-axis manual) |
| Angle | Fixed downward (~45°) |
| Distance to object | 30-50 cm typical |

---

## Wiring Diagram Summary

```
ESP32-CAM                          Arduino Nano
┌─────────────────┐               ┌─────────────────┐
│  GPIO 13 (TX) ──┼───────────────┤ D0 (RX)         │
│  GPIO 12 (RX) ──┼───────────────┤ D1 (TX)         │
│  GPIO 4  ───────┼───────────────┤ RESET           │
│  GND ───────────┼───────────────┤ GND             │
└─────────────────┘               └─────────────────┘
                                            │
                                 ┌──────────┼──────────┐
                                 ▼          ▼          ▼
                            ┌─────────┐ ┌─────────┐ ┌─────────┐
                            │ DHT22   │ │ Soil    │ │ LCD     │
                            │ (D10)   │ │ (A0)    │ │ (A4/A5) │
                            └─────────┘ └─────────┘ └─────────┘
                                            │
                                 ┌──────────┼──────────┐
                                 ▼          ▼          ▼
                            ┌─────────┐ ┌─────────┐ ┌─────────┐
                            │ Stepper │ │ Heater  │ │ Fans    │
                            │ (D7/D8/ │ │ (D5)    │ │ (D11/   │
                            │  D9)    │ │         │ │  D13)   │
                            └─────────┘ └─────────┘ └─────────┘
```

---

## Safety & Compliance

### Electrical
- All high-power components (stepper, heater) on separate supply rails
- Common ground enforced
- Flyback diodes on inductive loads (stepper, fans)
- Thermal fuse on heater circuit recommended

### Mechanical
- Homing switch prevents over-rotation
- Stepper current limiting via driver (DRV8825: 1.5A default)
- Emergency stop: `<X>` command disables motor immediately

### Environmental
- Operating temp: 10-40°C (DHT22 range)
- Humidity: 10-90% RH non-condensing
- Enclosure: IP20 minimum (indoor use)

---

## Firmware Build Configuration

### ESP32 (PlatformIO)

```ini
[env:esp32cam]
platform = espressif32
board = esp32cam
framework = arduino
monitor_speed = 115200
lib_deps =
    ArduinoJson@^6.21.0
    ESPAsyncWebServer
    AsyncTCP
    SD_MMC
build_flags =
    -DARDUINO_USB_CDC_ON_BOOT=0
```

### Arduino Nano (PlatformIO)

```ini
[env:nanoatmega328]
platform = atmelavr
board = nanoatmega328
framework = arduino
monitor_speed = 115200
lib_deps =
    LiquidCrystal_I2C
    DHT sensor library
build_flags =
    -D DHTPIN=10
    -D DHTTYPE=DHT22
```

---

## Debugging Interfaces

| Interface | Purpose | Access |
|-----------|---------|--------|
| ESP32 Serial (USB) | Boot logs, `logSD()` output | USB-CDC |
| Arduino Serial (USB) | Telemetry, command echo | USB-CDC |
| ESP32 Web Dashboard | Status, capture test | `http://192.168.4.1` |
| Arduino LCD | Runtime status, errors | Physical display |