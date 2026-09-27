# AntaresLab AGENTS.md

Repository for AntaresStudio — a photogrammetry-based 3D scanning system with IoT hardware (ESP32-CAM + Arduino) and multiple software frontends.

---

## Architecture Overview

This is a **multi-project monorepo** with one **active production system** (AntaresStudio IoT), one **active landing website** (AntaresWeb), one **documentation portal** (AntaresDocs — incomplete), and several **legacy/prototype** directories.

### Active / Current Production

| Project | Path | Stack | Status |
|---------|------|-------|--------|
| **AntaresStudio IoT — Flutter App** | `AntaresStudio/AntaresStudioIoT/app/` | Flutter (Windows desktop) | Primary UI |
| **AntaresStudio IoT — Backend** | `AntaresStudio/AntaresStudioIoT/backend/` | FastAPI (rembg + Meshroom) | Primary backend |
| **AntaresStudio IoT — ESP32 Firmware** | `AntaresStudio/AntaresStudioIoT/firmware_esp/` | Arduino/PlatformIO | Current gateway |
| **AntaresStudio IoT — Arduino Firmware** | `AntaresStudio/AntaresStudioIoT/firmware_arduino/` | Arduino/PlatformIO | Current controller |
| **AntaresWeb** | `AntaresWeb/` | Static HTML | Landing/product site |

### Documentation (Incomplete)
- `AntaresDocs/` — React/Vite documentation portal; content needs cleanup

### Legacy / Prototype (Do Not Modify)
- `AntaresStudio/archive/` — Legacy PyQt6 desktop application
- `AntaresElectronics/` — Legacy electronics/firmware
- `AntaresStudio/backend/` — Old COLMAP/Open3D backend prototype
- `AntaresStudio/frontend/` — Old React/Vite/Three.js prototype
- `AntaresBitis/` — Duplicate/temporary old variant (planned for removal in Phase 3A)

---

## Key Commands (Verified from Repository)

### AntaresStudio IoT — Primary System
```bash
# Python Backend (port 8000)
cd AntaresStudio/AntaresStudioIoT/backend
pip install -r requirements.txt
python -m app.main          # or: python run_backend.py

# Flutter Windows App
cd AntaresStudio/AntaresStudioIoT/app
flutter pub get
flutter run -d windows      # Windows desktop target
```

### AntaresWeb
```bash
# Static site — open index.html directly or serve with any static server
cd AntaresWeb
# e.g., python -m http.server 8080
```

### AntaresDocs
```bash
cd AntaresDocs
npm install
npm run dev
```

### Firmware Build
> The repository contains PlatformIO configuration files (`platformio.ini`) in both firmware directories. The exact build commands are repository-dependent; inspect each `platformio.ini` for targets and environments.

---

## Critical Architecture Details (Non-Obvious)

### ESP32-CAM Runs in **AP Mode** (Not Station)
- SSID: `ANTARES_KAPSUL_LAB` (configurable in `credentials.h`)
- Fixed IP: `192.168.4.1`
- PC **must connect to this Wi-Fi** for auto-discovery to work
- Backend auto-discovers ESP32 on startup and registers its IP

### Communication Flow
```
Flutter App (Windows) ←→ ESP32-CAM (192.168.4.1:80) ←UART→ Arduino Nano
         ↓ HTTP (localhost:8000)
    Python Backend (rembg + Meshroom)
```

### UART Protocol (Arduino ↔ ESP32) — HARDWARE CONSTRAINT
- **Baud**: 115200
- **Arduino → ESP32**: `CEK` (capture), `360_START`, `360_END`, `DATA,temp,hum,soil,heater,fanSly,fanDz,mode`
- **ESP32 → Arduino**: `<CMD>` bracketed commands
  - `<H>` Home, `<R,angle>` Rotate, `<G>` Start Scan, `<X>` Cancel
  - `<P>` Pause Autonomous, `<C>` Continue Autonomous
  - `<S>` Status Request, `<E>` Enable Motor, `<D>` Disable Motor
- **Do not change** without hardware validation

### Autonomous Operation (Arduino-First)
- Arduino runs 5-min timer (`AUTO_SCAN_INTERVAL = 300000ms`)
- On timeout: sends `CEK` → ESP32 captures → saves to SD (if PC offline) or routes to PC
- **PC commands rejected with `BUSY`** when Arduino state ≠ IDLE (except `<X>` cancel)

### Image Routing (Hybrid)
- ESP32 checks PC heartbeat (`http://192.168.4.2:8000/api/ping` cached 3s)
- PC reachable → direct HTTP (Flutter polls `/api/capture`)
- PC unreachable → save to SD card (`/session_{timestamp}/img_{timestamp}.jpg`)

### ESP32 SD_MMC Configuration — HARDWARE CONSTRAINT
- **1-bit mode** (GPIO 2=D0, 14=CLK, 15=CMD)
- Frees GPIO 12/13 for UART2 to Arduino
- Do not change without hardware validation

### ESP32 GPIO Mapping — HARDWARE CONSTRAINT
| Function | GPIO |
|----------|------|
| UART2 TX → Arduino RX | 13 |
| UART2 RX ← Arduino TX | 12 |
| Arduino RESET | 4 |
| SD_MMC D0/CLK/CMD | 2/14/15 |
| Camera pins | Per `firmware_esp/firmware_esp.ino` |

### Flutter `BackendProcessManager` — HARDWARE CONSTRAINT
- Auto-starts Python backend on Windows via `BackendProcessManager`
- Assumes backend executable at `../backend/run_backend.py` or `python -m app.main`
- Do not change path assumptions without updating Flutter code

---

## Python Backend (IoT) — Key Endpoints

| Endpoint | Purpose |
|----------|---------|
| `POST /api/v1/photos/upload` | Upload JPEG from Flutter |
| `POST /api/v1/photos/clean/{sid}` | Background rembg processing |
| `GET /api/v1/photos/status/{sid}` | Session status |
| `POST /api/v1/pipeline/start/{sid}` | Start Meshroom pipeline (async) |
| `GET /api/v1/pipeline/status/{pid}` | Pipeline progress (polling) |
| `GET /api/v1/pipeline/model/{pid}` | Download 3D model (.glb) |
| `GET /api/telemetry` | Latest capsule telemetry |
| `POST /api/telemetry` | Receive telemetry from ESP32/Flutter |
| `GET /health` | Health check + ESP32 registration status |
| `GET /api/esp32/status` | Network interface debug |

---

## Flutter App — Provider Structure
- `DeviceProvider` — ESP32 connection, telemetry, camera stream
- `ScanProvider` — Scan orchestration, SD sync, photo management
- `BlackBoxProvider` — Firmware update management

---

## Common Gotchas

1. **PC must join ESP32 AP** (`ANTARES_KAPSUL_LAB`) before starting backend — auto-discovery fails otherwise
2. **Backend binds to 0.0.0.0:8000** — firewall must allow inbound on Wi-Fi interface
3. **Flutter auto-starts backend** on Windows — don't run duplicate `python -m app.main`
4. **Arduino watchdog** (4s) — long motor moves must feed WDT (handled in `updateMotor()`)
5. **ESP32 WDT** (10s) — SD writes chunked with `yield()` and `esp_task_wdt_reset()`
6. **CORS** — Backend allows `*`; ESP32 HTTP handlers set `Access-Control-Allow-Origin: *`

---

## Testing / Verification

```bash
# Backend health
curl http://localhost:8000/health

# ESP32 status (when connected to AP)
curl http://192.168.4.1/api/status

# Arduino telemetry (via ESP32)
curl http://192.168.4.1/api/arduino/status

# Capture test
curl http://192.168.4.1/api/capture --output test.jpg
```

---

## Future Repository Structure (Planned — NOT Implemented)

```text
antareslab/
├── .github/
├── apps/
│   └── desktop/
├── services/
│   └── photogrammetry-api/
├── firmware/
│   ├── controller-arduino/
│   └── gateway-esp32cam/
├── hardware/
│   ├── schematics/
│   ├── cad-models/
│   └── pinouts/
├── web/
│   ├── landing/
│   └── docs/
├── docs/
│   ├── architecture/
│   ├── api/
│   └── specs/
└── archive/
    ├── legacy-desktop-pyqt/
    ├── legacy-electronics/
    └── prototypes/
```

**Current phase**: Phase 3A — Safe Cleanup (targets: `AntaresBitis/`, `analyze_output.txt`, `analyze2.txt`, unused `*_v3` files, unused firmware snippets, `AntaresWeb/archive/`, generated/test image data, generated 3D output). **These have not been removed yet.**

---

## Git Safety Rules

- Never commit or push unless explicitly instructed.
- Prefer reversible Git operations.
- Before destructive operations, inspect references/dependencies first.
- Do not rewrite Git history unless explicitly instructed.
- Do not delete active code based only on filenames.
- For repository restructuring, verify path dependencies before moving files.
- Hardware and protocol changes are separate from repository organization and should not be mixed into cleanup operations.

---

## References

- `yeni_implementation_plan.md` — Detailed refactoring plan (v2 architecture)
- `implementation_plan.md` — Original web migration plan
- `AntaresStudio/AntaresStudioIoT/README.md` — IoT system overview
- `AntaresStudio/AntaresStudioIoT/backend/app/main.py` — Backend entrypoint with lifespan
- `AntaresStudio/AntaresStudioIoT/app/lib/main.dart` — Flutter app entrypoint