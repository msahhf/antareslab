# Security Policy

## Supported Versions

AntaresLab is in active development. Security updates are provided for the latest stable release on the `main` branch.

| Version | Supported |
|---------|-----------|
| Latest `main` | ✅ Yes |
| `develop` branch | ⚠️ Best effort |
| Older releases | ❌ No |

---

## Reporting a Vulnerability

**Do not open public issues for security vulnerabilities.**

### Reporting Process

1. **Email**: Send details to **security@antareslab.example** (placeholder — configure actual contact)
2. **Include**:
   - Component affected (Flutter app, backend, ESP32 firmware, Arduino firmware, docs portal)
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)
3. **Response time**: Acknowledgment within 72 hours; triage within 7 days

### What to Expect

- Acknowledgment of receipt
- Initial severity assessment
- Timeline for fix (if accepted)
- Coordinated disclosure timeline (typically 90 days)

---

## Credential & Secret Management

### Never Commit

| Secret Type | Example | Prevention |
|-------------|---------|------------|
| WiFi Credentials | `AP_SSID`, `AP_PASSWORD` in `credentials.h` | Use `credentials.h.example` template |
| Environment Variables | `.env` with API keys, tokens | Use `.env.example` template |
| API Keys | Backend service keys | Environment-only injection |
| Database Passwords | SQLite/PostgreSQL credentials | Not in repo |
| Personal Paths | `/home/user/...`, `C:\Users\...` | Use relative paths or env vars |

### Template Files (Safe to Commit)

| Template | Purpose |
|----------|---------|
| `firmware/gateway-esp32cam/credentials.h.example` | ESP32 WiFi AP config template |
| `services/photogrammetry-api/.env.example` | Backend environment template |

**Workflow:**
```bash
# ESP32
cp firmware/gateway-esp32cam/credentials.h.example firmware/gateway-esp32cam/credentials.h
# Edit credentials.h with real values (gitignored)

# Backend
cp services/photogrammetry-api/.env.example services/photogrammetry-api/.env
# Edit .env with real values (gitignored)
```

### Gitignore Protection

Root `.gitignore` and component-level `.gitignore` files exclude:
- `credentials.h`
- `.env`, `.env.*`, `*.env` (except `.env.example`)
- `*.log`, `build/`, `dist/`, `__pycache__/`
- IDE artifacts (`.vscode/`, `.idea/`, `*.swp`)

---

## Component-Specific Security

### Flutter Desktop App (`apps/desktop/`)

- **Backend auto-start**: `BackendProcessManager` spawns local Python process on Windows
- **No network exposure** beyond localhost:8000 and ESP32 AP (192.168.4.1)
- **No credential storage** in app; uses runtime config
- **Update mechanism**: Downloads from GitHub Releases; verifies via checksum (to be implemented)

### FastAPI Backend (`services/photogrammetry-api/`)

- **Binds to**: `0.0.0.0:8000` (all interfaces) — firewall must restrict to trusted networks
- **CORS**: Allows `*` (development); restrict in production
- **Authentication**: None currently (local network only); planned for production
- **File uploads**: JPEG/PNG only, max 50MB, size validation
- **Path traversal**: Uses `pathlib.Path` with resolved paths; session-scoped directories

### ESP32-CAM Firmware (`firmware/gateway-esp32cam/`)

- **WiFi**: AP mode only (`ANTARES_KAPSUL_LAB`), WPA2-PSK (min 8 chars)
- **HTTP endpoints**: No authentication (local AP network only)
- **UART bridge**: STK500 passthrough for Arduino OTA — physical access required
- **SD card**: 1-bit mode; files written in timestamped session folders
- **OTA**: HTTP upload endpoints (`/api/ota/esp32`, `/api/ota/arduino`) — local network only

### Arduino Nano Firmware (`firmware/controller-arduino/`)

- **Physical access required** for firmware changes (UART/STK500)
- **No wireless interface** — commands via ESP32 UART bridge only
- **Watchdog**: 4s timeout prevents lockup
- **Motor safety**: Homing limit (2000 steps), watchdog-fed steps

---

## Vulnerability Categories

### High Severity

- Remote code execution (RCE)
- Authentication bypass
- Arbitrary file read/write
- Privilege escalation
- Hardware safety violation (uncontrolled motor, thermal runaway)

### Medium Severity

- Information disclosure (logs, paths, internal state)
- Denial of service (resource exhaustion, watchdog trigger)
- CSRF/CORS misconfiguration
- Insecure default credentials

### Low Severity

- Information leakage in error messages
- Missing security headers
- Outdated dependencies (non-exploitable)

---

## Dependency Security

### Monitoring

- **Flutter**: `flutter pub outdated` + `flutter pub upgrade --major-versions` review
- **Python**: `pip-audit` or `pip list --outdated` + `pip install --upgrade`
- **Node.js**: `npm audit` + `npm audit fix`
- **PlatformIO**: `pio pkg update` + library version review

### Policy

- Update dependencies quarterly or when CVEs are published
- Pin versions in `pubspec.yaml`, `requirements.txt`, `package.json`
- Test thoroughly after updates (especially firmware libraries)

---

## Hardware Safety

**Security issues affecting physical hardware are treated as Critical:**

- Uncontrolled motor movement
- Thermal runaway (heater without feedback)
- Watchdog bypass
- Firmware corruption leading to unsafe state

Report hardware safety issues immediately via the vulnerability reporting process.

---

## Disclosure Timeline

| Phase | Timeline |
|-------|----------|
| Acknowledgment | ≤ 72 hours |
| Triage & Severity | ≤ 7 days |
| Fix Development | ≤ 30 days (High), ≤ 90 days (Medium/Low) |
| Coordinated Disclosure | 90 days from acknowledgment |
| Public Advisory | After fix released + grace period |

---

## Contact

**Security Contact**: *Configure actual contact — placeholder below*

- **Email**: security@antareslab.example
- **PGP Key**: *Add if available*

> **Note**: This is a placeholder. Project maintainers must configure actual security contact information before public release.

---

## Security Checklist for Contributors

- [ ] No secrets in commit (check `git diff --cached`)
- [ ] `.env` and `credentials.h` not staged
- [ ] Dependencies updated with security patches
- [ ] Hardware safety validated (if firmware changed)
- [ ] No new attack surface introduced without review
- [ ] Error messages don't leak internal paths/stack traces