# UART Protocol Specification

## Overview

**Physical Layer:** UART 115200 8N1 (8 data bits, No parity, 1 stop bit)
**Connection:** ESP32-CAM UART2 (GPIO 12 RX, GPIO 13 TX) ↔ Arduino Nano Hardware Serial (D0/D1)
**Arduino RESET:** ESP32 GPIO 4 → Arduino RESET pin (for STK500 bridge)

---

## Message Formats

### Arduino → ESP32 (Newline-Terminated)

All messages end with `\n` (ASCII 0x0A). ESP32 reads until newline.

#### 1. Telemetry (Periodic, ~1 Hz)

```
DATA,<temp>,<humidity>,<soil>,<heater>,<fanSly>,<fanDz>,<mode>\n
```

| Field | Type | Range | Description |
|-------|------|-------|-------------|
| temp | float | -40.0 to 80.0 | DHT22 temperature °C |
| humidity | int | 0-100 | DHT22 humidity % |
| soil | int | 0-1023 | Analog soil moisture (A0) |
| heater | int | 0-255 | PWM heater power |
| fanSly | 0/1 | — | Salyangoz fan state |
| fanDz | 0/1 | — | Düz fan state |
| mode | string | OTONOM/MANUEL | Current mode |

**Example:**
```
DATA,25.3,60,512,128,1,0,OTONOM\n
```

#### 2. Capture Request (Autonomous)

```
CEK\n
```
Sent by Arduino every 5 minutes in autonomous mode, or during 360° scan sequence.

#### 3. Scan Markers

```
360_START\n
```
Sent when Arduino begins autonomous 360° scan.

```
360_END\n
```
Sent when Arduino completes 8-shot rotation.

---

### ESP32 → Arduino (Bracketed Commands)

All commands wrapped in `<` and `>`. Arduino parses between brackets.

Format: `<COMMAND>\n` or `<COMMAND,PARAM>\n`

| Command | Parameters | Description | Arduino Response |
|---------|------------|-------------|------------------|
| `H` | — | Move to home position | `OK,HOMING` |
| `R` | angle (float) | Rotate to absolute angle | `OK,ROT` |
| `G` | — | Start 360° scan (8 shots × 45°) | `OK,SCAN_START` |
| `X` | — | Cancel current operation | `OK,CANCEL` |
| `P` | — | Pause autonomous (enter manual) | `OK,MANUAL` |
| `C` | — | Continue autonomous | `OK,AUTO` |
| `S` | — | Request status telemetry | `OK,<temp>,<hum>,<soil>,<heater>,<fanSly>,<fanDz>,<mode>` |
| `E` | — | Enable stepper motor | `OK,EN` |
| `D` | — | Disable stepper motor | `OK,DIS` |
| `V` | speed (int) | Set motor step delay (µs) | `OK,SPD` |

**Examples:**
```
<H>\n
<R,90.0>\n
<G>\n
<R,45.5>\n
<V,800>\n
```

---

### Arduino → ESP32 Responses (Newline-Terminated)

| Response | Context |
|----------|---------|
| `PONG` | Ping response |
| `OK,HOMING` | Home command accepted |
| `OK,ROT` | Rotate command accepted |
| `OK,SCAN_START` | Scan started |
| `OK,CANCEL` | Operation cancelled |
| `OK,MANUAL` | Manual mode entered |
| `OK,AUTO` | Autonomous mode resumed |
| `OK,EN` | Motor enabled |
| `OK,DIS` | Motor disabled |
| `OK,SPD` | Speed set |
| `OK,<temp>,<hum>,<soil>,<heater>,<fanSly>,<fanDz>,<mode>` | Status response |
| `BUSY` | Rejected (system scanning/homing) |
| `ERR,CMD` | Unknown command |
| `OK,CAP` | Capture successful (to ESP32) |
| `ERR,CAP` / `ERR,CAP_FAIL` | Capture failed |
| `360_END` | Scan sequence complete |

---

## Autonomous Scan Flow

```
Arduino (5-min timer)                    ESP32
      |                                      |
      |--- CEK ----------------------------->| (capture request)
      |                                      |--- routeImage() ---> SD or direct
      |                                      |
      |<-- OK,CAP ---------------------------| (capture confirmed)
      |                                      |
      |--- <R,45> -------------------------->| (rotate 45°)
      |                                      |--- Serial2.print("<R,45>")
      |                                      |
      |<-- OK,ROT ---------------------------| (rotation done)
      |                                      |
      |   (repeat 8x: CEK → OK,CAP → <R,45> → OK,ROT)
      |                                      |
      |--- 360_END ------------------------->| (scan complete)
```

---

## Error Handling

### ESP32 → Arduino Timeout

- ESP32 waits **5 seconds** for Arduino response after sending `<CMD>`
- On timeout: returns `TIMEOUT` to HTTP caller
- Arduino may still process command after timeout

### Arduino Capture Timeout

- Arduino waits **10 seconds** for `OK,CAP` after sending `CEK`
- On timeout: proceeds to next shot, logs `CAP TIMEOUT` on LCD

### Arduino Command Rejection

When `currentState != IDLE` (scanning/homing), Arduino rejects all commands **except `X` (Cancel)**:
```
<H>  →  BUSY
<R,90>  →  BUSY
<X>  →  OK,CANCEL  (always accepted)
```

---

## UART Buffer Constraints

| Buffer | Size | Handling |
|--------|------|----------|
| Arduino RX (bracketed) | 64 chars | Truncates at 63 |
| Arduino RX (telemetry) | 64 chars | Truncates at 63 |
| ESP32 TX (command) | 128 chars | JSON + brackets |
| ESP32 RX (telemetry) | 64 chars | Line-by-line parse |

---

## Electrical Characteristics

| Parameter | Value |
|-----------|-------|
| Baud Rate | 115200 bps |
| Data Bits | 8 |
| Parity | None |
| Stop Bits | 1 |
| Logic Level | 3.3V (ESP32) ↔ 5V tolerant (Arduino Nano) |
| Flow Control | None |

---

## Pin Mapping

| ESP32 Pin | Arduino Pin | Function |
|-----------|-------------|----------|
| GPIO 13 (UART2 TX) | D0 (RX) | ESP32 → Arduino |
| GPIO 12 (UART2 RX) | D1 (TX) | Arduino → ESP32 |
| GPIO 4 | RESET | ESP32 → Arduino RESET (STK500 bridge) |
| GND | GND | Common ground |

---

## SDMMC 1-Bit Mode (Enables UART2)

| SD Pin | GPIO | Note |
|--------|------|------|
| D0 | 2 | Data |
| CLK | 14 | Clock |
| CMD | 15 | Command |

Using 1-bit mode frees GPIO 12/13 for UART2.

---

## Implementation Notes

### Arduino Parser (firmware_arduino.ino)

- **Bracketed commands**: Peeks for `<`, reads until `>`, processes via `processCommand()`
- **Telemetry responses**: Reads lines ending in `\n`, stores in `responseBuf`
- **Non-blocking**: Uses `Serial.peek()` to avoid blocking on mixed traffic

### ESP32 Handler (firmware_esp.ino)

- **Command forwarding**: `/api/arduino/command` → `Serial2.print("<" + cmd + ">")`
- **Response wait**: 5s max, reads lines until `\n` or `\r`
- **Telemetry parsing**: `parseArduinoTelemetry()` splits `DATA,` CSV
- **Capture trigger**: `CEK` → `routeImage()` → `Serial2.println("OK,CAP")`

---

## Testing Commands

### Manual Arduino Test (Serial Monitor)
```
<H>          # Home
<R,90>       # Rotate 90°
<G>          # Start scan
<X>          # Cancel
<S>          # Status
```

### ESP32 HTTP Test
```bash
# Capture
curl http://192.168.4.1/api/capture --output test.jpg

# Arduino command
curl -X POST http://192.168.4.1/api/arduino/command \
  -H "Content-Type: application/json" \
  -d '{"cmd":"H"}'

# Status
curl http://192.168.4.1/api/status
```

### Arduino Telemetry Format Verification
```
DATA,25.3,60,512,128,1,0,OTONOM
  │    │   │   │    │  │  └── mode
  │    │   │   │    │  └── fanDz (0/1)
  │    │   │   │    └── fanSly (0/1)
  │    │   │   └── heater PWM (0-255)
  │    │   └── soil moisture (0-1023)
  │    └── humidity (0-100%)
  └── temperature (°C, 1 decimal)
```