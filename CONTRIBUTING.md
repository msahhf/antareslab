# Contributing to AntaresLab

Thank you for your interest in contributing to AntaresLab. This document outlines the guidelines for contributing to this photogrammetry-based 3D scanning system.

---

## Project Overview

AntaresLab is a multi-component system:
- **Flutter Desktop App** (`apps/desktop/`) — Windows UI for scan control, gallery, OTA updates
- **FastAPI Backend** (`services/photogrammetry-api/`) — Photogrammetry pipeline (rembg + Meshroom)
- **ESP32-CAM Firmware** (`firmware/gateway-esp32cam/`) — WiFi AP gateway, camera, UART bridge
- **Arduino Firmware** (`firmware/controller-arduino/`) — Motor, climate, autonomous scan
- **Documentation Portal** (`web/docs/`) — React/Vite technical documentation

---

## Repository Structure

```
antareslab/
├── apps/desktop/                 # Flutter Windows app
├── services/photogrammetry-api/  # FastAPI backend
├── firmware/
│   ├── controller-arduino/       # Arduino Nano firmware
│   └── gateway-esp32cam/         # ESP32-CAM firmware
├── web/
│   ├── landing/                  # Static landing site
│   └── docs/                     # React/Vite documentation portal
├── docs/
│   ├── architecture/             # Architecture documentation
│   ├── api/                      # API reference
│   └── specs/                    # Technical specifications
├── archive/                      # Legacy/prototype code (do not modify)
└── hardware/                     # Hardware designs (future)
```

---

## Development Setup

### Prerequisites

- **Flutter**: SDK 3.22+ (stable), Windows target
- **Python**: 3.10+, `pip`, `uvicorn`, `fastapi`
- **PlatformIO**: For firmware builds
- **Node.js**: 18+, for documentation portal

### Quick Start

```bash
# Flutter App
cd apps/desktop && flutter pub get && flutter run -d windows

# Backend
cd services/photogrammetry-api && pip install -r requirements.txt && python -m app.main

# ESP32 Firmware
cd firmware/gateway-esp32cam && pio run -e esp32cam

# Arduino Firmware
cd firmware/controller-arduino && pio run -e nanoatmega328

# Documentation Portal
cd web/docs && npm install && npm run dev
```

---

## Branching Strategy

| Branch | Purpose |
|--------|---------|
| `main` | Stable releases only |
| `develop` | Integration branch for features |
| `feature/*` | New features (from `develop`) |
| `fix/*` | Bug fixes (from `develop` or `main`) |
| `cleanup/*` | Repository maintenance (e.g., `cleanup/phase-1-phase-3a`) |

**Rules:**
- All changes target `develop` unless it's a hotfix for `main`
- Feature branches: `feature/<short-description>`
- Fix branches: `fix/<short-description>`
- Delete merged branches

---

## Commit Conventions

Follow [Conventional Commits](https://www.conventionalcommits.org/):

| Type | Description |
|------|-------------|
| `feat:` | New feature |
| `fix:` | Bug fix |
| `refactor:` | Code restructuring without behavior change |
| `chore:` | Maintenance, build, tooling |
| `docs:` | Documentation only |
| `test:` | Adding/updating tests |
| `perf:` | Performance improvement |

**Examples:**
```
feat: add SD card health monitoring to ESP32
fix: resolve pipeline cancellation race condition
refactor: restructure repository into monorepo layout
docs: add UART protocol specification
chore: update Flutter dependencies
```

**Hardware-related commits** must include `hardware:` scope:
```
feat(hardware): add DHT22 retry logic
fix(hardware): correct stepper homing direction
```

---

## Pull Request Process

1. **Open PR against `develop`** (or `main` for hotfixes)
2. **Fill PR template** completely
3. **All checks must pass**: `flutter analyze`, `flutter test`, `python -m pytest` (when available), ESLint
4. **Code review**: At least one approval required
5. **Squash merge** into target branch
6. **Delete source branch** after merge

### PR Checklist

- [ ] Code compiles and runs locally
- [ ] Tests pass (`flutter test`, backend tests if applicable)
- [ ] Linting passes (`flutter analyze`, `eslint`, `ruff`/`flake8` if configured)
- [ ] Documentation updated (README, API docs, architecture docs if applicable)
- [ ] No secrets/credentials committed
- [ ] Hardware changes validated on physical device (if applicable)

---

## Testing Expectations

| Component | Testing Approach |
|-----------|------------------|
| Flutter App | `flutter test` (unit + widget tests) |
| Backend | Manual API testing via Swagger (`/docs`); unit tests when added |
| Firmware | Hardware validation on physical device required |
| Documentation | `npm run lint`, manual navigation review |

**Note:** Firmware changes **must** be tested on physical hardware before merging. Simulation-only validation is insufficient for motor control, UART timing, or thermal systems.

---

## Documentation Expectations

- **Public-facing docs** (README, `docs/`, `web/docs/`) must be in English
- **Code comments** may be Turkish or English; prefer English for public APIs
- **API changes** require corresponding `docs/api/` updates
- **Architecture changes** require `docs/architecture/` updates
- **Hardware/protocol changes** require `docs/specs/` updates

---

## Hardware Contribution Guidance

### Firmware Safety Requirements

**Any change to firmware must address:**

1. **UART Protocol Integrity**
   - Baud rate: 115200 8N1 (do not change)
   - Message format: `<CMD>` for ESP32→Arduino, `DATA,...` for Arduino→ESP32
   - Response handling: timeouts, retries, error codes

2. **Pin Mapping Stability**
   - GPIO assignments are hardware-constrained
   - Do not change UART, SD_MMC, camera, or motor pins without hardware validation
   - See `docs/specs/hardware-interface.md` for current mapping

3. **Motor & Thermal Safety**
   - Stepper: 4.55 steps/deg, 800µs step delay, watchdog-fed
   - Homing: Hall switch on D6, max 2000 steps safety limit
   - Climate: DHT22, dual fans, PWM heater — PID closed-loop
   - Watchdog: 4s (Arduino), 10s (ESP32) — must be fed in long operations

4. **Autonomous Behavior**
   - 5-minute scan interval (300,000 ms)
   - Priority rejection: `BUSY` when state ≠ IDLE (except `<X>` cancel)
   - Emergency commands: `<P>` pause, `<X>` cancel — always processed

### Hardware Validation Checklist

Before submitting firmware PRs:

- [ ] Compiles for target (`pio run -e esp32cam` / `pio run -e nanoatmega328`)
- [ ] Flashes to physical device without errors
- [ ] UART communication verified (logic analyzer or serial monitor)
- [ ] Motor rotation/homing tested mechanically
- [ ] Climate control loop stable (no oscillation)
- [ ] Autonomous scan completes 8-shot rotation
- [ ] SD card fallback works when PC disconnected
- [ ] OTA/STK500 bridge functional (if modified)

### Separation of Concerns

**Hardware/protocol changes** are **separate** from:
- Repository organization changes
- Documentation updates
- Build system changes

Do not mix hardware logic modifications with refactoring or documentation PRs.

---

## Credential & Security Policy

**Never commit secrets:**

- WiFi credentials (`credentials.h`)
- API keys, tokens, database passwords
- `.env` files with real values
- Personal filesystem paths

**Use example files instead:**

- `credentials.h.example` → copy to `credentials.h` (gitignored)
- `.env.example` → copy to `.env` (gitignored)

**Report security issues** via [SECURITY.md](SECURITY.md) process.

---

## Code Style

| Language | Style Guide |
|----------|-------------|
| Dart/Flutter | `flutter analyze` (default lints) |
| Python | PEP 8, type hints preferred |
| C++ (Arduino/ESP32) | Arduino style, consistent naming |
| JavaScript/React | ESLint (Airbnb-ish), Prettier formatting |
| Markdown | Sentence case headings, English prose |

Run linters before committing:
```bash
flutter analyze          # apps/desktop
cd services/photogrammetry-api && ruff check .  # or flake8
cd web/docs && npm run lint
```

---

## Hardware Contributors

If you are contributing firmware or hardware designs:

1. **Identify yourself** as a hardware contributor in PR description
2. **Reference hardware validation** (photos, logs, test results)
3. **Do not modify** `archive/` contents
4. **Coordinate** protocol changes with backend/flutter maintainers

---

## Questions?

Open a GitHub Discussion or issue for clarification before starting significant work.