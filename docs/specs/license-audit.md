# License Audit

## Current License Status

### Repository License

**Apache-2.0 License applied.** Root `LICENSE` file added with full Apache License 2.0 text. `NOTICE` file created with third-party attributions.

### Previously Restrictive License (Removed)

The following restrictive license was removed from the repository:
- **File:** `services/photogrammetry-api/setup_prep/assets/LICENSE.txt` (deleted)
- **Content:** "All rights reserved" - prohibited copying, distribution, reverse engineering
- **Referenced by:** `services/photogrammetry-api/setup_prep/installer_config.iss` (updated to reference root `LICENSE`)

This restrictive license has been removed and replaced with Apache-2.0.

---

## Third-Party Dependencies

### Desktop App (`apps/desktop/pubspec.yaml`)

| Dependency | Version | License | Source |
|------------|---------|---------|--------|
| flutter | SDK | BSD-3-Clause | flutter.dev |
| http | ^1.2.0 | BSD-3-Clause | pub.dev |
| provider | ^6.1.0 | MIT | pub.dev |
| path_provider | ^2.1.0 | BSD-3-Clause | pub.dev |
| cupertino_icons | ^1.0.6 | MIT | pub.dev |
| url_launcher | ^6.2.0 | BSD-3-Clause | pub.dev |
| flutter_test | SDK | BSD-3-Clause | flutter.dev |
| flutter_lints | ^3.0.0 | BSD-3-Clause | pub.dev |

**All Flutter dependencies: BSD-3-Clause or MIT (permissive)**

### Backend (`services/photogrammetry-api/requirements.txt`)

| Dependency | Version | License | Source |
|------------|---------|---------|--------|
| fastapi | >=0.109.0 | MIT | PyPI |
| uvicorn[standard] | >=0.27.0 | BSD-3-Clause | PyPI |
| python-multipart | >=0.0.9 | MIT | PyPI |
| rembg | >=2.0.50 | MIT | PyPI |
| Pillow | >=10.2.0 | HPND (MIT-like) | PyPI |
| numpy | >=1.26.0 | BSD-3-Clause | PyPI |
| trimesh | >=4.0.0 | MIT | PyPI |
| pyglet | >=2.0.0 | BSD-3-Clause | PyPI |
| pydantic | >=2.5.0 | MIT | PyPI |
| pydantic-settings | >=2.0.0 | MIT | PyPI |
| aiofiles | >=23.2.0 | Apache-2.0 | PyPI |
| python-dotenv | >=1.0.0 | MIT | PyPI |
| httpx | >=0.27.0 | BSD-3-Clause | PyPI |

**All Python dependencies: MIT, BSD-3-Clause, or Apache-2.0 (permissive)**

### Documentation Portal (`web/docs/package.json`)

| Dependency | Version | License | Source |
|------------|---------|---------|--------|
| react | ^19.2.0 | MIT | npm |
| react-dom | ^19.2.0 | MIT | npm |
| react-router-dom | ^7.13.0 | MIT | npm |
| react-syntax-highlighter | ^16.1.0 | MIT | npm |
| lucide-react | ^0.563.0 | ISC | npm |
| cmdk | ^1.1.1 | MIT | npm |
| tailwindcss | ^4.1.18 | MIT | npm |
| @tailwindcss/vite | ^4.1.18 | MIT | npm |
| vite | ^7.2.4 | MIT | npm |
| eslint | ^9.39.1 | MIT | npm |
| @eslint/js | ^9.39.1 | MIT | npm |
| eslint-plugin-react-hooks | ^7.0.1 | MIT | npm |
| eslint-plugin-react-refresh | ^0.4.24 | MIT | npm |
| globals | ^16.5.0 | MIT | npm |

**All npm dependencies: MIT or ISC (permissive)**

### Landing Page (`web/landing/index.html`)

| Resource | License | Notes |
|----------|---------|-------|
| Fontshare (Clash Display, Inter, JetBrains Mono) | Free for commercial use | fontshare.com |
| Google Fonts (Inter, JetBrains Mono) | SIL Open Font License 1.1 | fonts.google.com |
| TailwindCSS CDN | MIT | tailwindcss.com |
| GSAP ^3.12.5 | GreenSock Standard License | Free for commercial use; Club GreenSock only for bonus plugins |
| Lenis @1.1.18 | MIT | github.com/darkroomengineering/lenis |

**Note:** GSAP standard license allows free commercial use. Club GreenSock membership is only required for bonus plugins (MorphSVG, DrawSVG, etc.), not for core GSAP/ScrollTrigger used in the landing page.

### Firmware Libraries (Arduino/PlatformIO)

| Library | License | Notes |
|---------|---------|-------|
| ESP-IDF (esp_camera, WiFi, ESPmDNS, esp_http_server, Update, Preferences, esp_task_wdt, SD_MMC, HTTPClient) | Apache-2.0 | Espressif Systems |
| ArduinoJson | MIT | Benoît Blanchon |
| ESPAsyncWebServer | LGPL-2.1 | me-no-dev |
| AsyncTCP | LGPL-2.1 | me-no-dev |
| SD_MMC (part of ESP-IDF) | Apache-2.0 | Espressif Systems |
| DHT sensor library | MIT | Adafruit / Various |
| LiquidCrystal_I2C | GPL-3.0 (verify variant) | Various |
| avr-libc (avr/wdt.h, Wire.h) | LGPL-2.1 / BSD-3-Clause | AVR Libc Developers |

**Note:** LGPL-2.1 dependencies (ESPAsyncWebServer, AsyncTCP) require dynamic linking or object file provision for static linking. Apache-2.0 is compatible with LGPL-2.1; GPL-3.0 is NOT.

---

## Software License Decision

**Chosen: Apache-2.0**

### Justification

| Criterion | Apache-2.0 | MIT | GPL-3.0 |
|-----------|------------|-----|---------|
| LGPL-2.1 Compatibility | ✅ Compatible | ✅ Compatible | ❌ Conflict |
| Patent Grant | ✅ Explicit | ❌ Implicit | ✅ Explicit |
| Commercial Use | ✅ | ✅ | ✅ (with source) |
| Binary Distribution | ✅ | ✅ | ⚠️ Requires source |
| Hardware/Firmware Suitability | ✅ Best | ✅ Good | ⚠️ Complex |
| Industry Adoption | High (Android, TensorFlow, ROS) | High (React, Node) | High (Linux) |

**Recommendation: Apache-2.0** — Best fit for hardware/software project with LGPL dependencies and potential patent considerations.

---

## Applied License Changes

### Files Modified

| File | Change |
|------|--------|
| `LICENSE` | Created with full Apache-2.0 text |
| `NOTICE` | Created with third-party attributions |
| `services/photogrammetry-api/setup_prep/installer_config.iss` | Updated `LicenseFile` to reference root `LICENSE` |
| `services/photogrammetry-api/setup_prep/assets/LICENSE.txt` | **Deleted** (was restrictive "All rights reserved") |
| Project source files | Added `SPDX-License-Identifier: Apache-2.0` headers |

### Source Files with SPDX Headers Added

| Category | Files |
|----------|-------|
| Python Backend | 15+ files in `services/photogrammetry-api/app/` and root |
| Flutter App | 25+ files in `apps/desktop/lib/` |
| Firmware | 2 files (`firmware_arduino.ino`, `firmware_esp.ino`, `credentials.h.example`) |
| Documentation Portal | 15+ files in `web/docs/src/` |

Files **NOT** modified (third-party/generated/excluded):
- `package-lock.json`, `pubspec.lock` (lock files)
- `package.json`, `pubspec.yaml`, `requirements.txt` (manifest files)
- `package.json` (web/docs), `pubspec.yaml` (Flutter)
- Documentation files (`.md` in `docs/`, `web/docs/`, root)
- Configuration files (`.yaml`, `.json`, `.toml`, `.ini` except where code)
- Lock files, vendor files, generated files
- Archive files

---

## Attribution Requirements (NOTICE)

The `NOTICE` file includes required attributions for:
- All Python, Dart, npm dependencies with their licenses
- Font licenses (Fontshare, Google Fonts SIL OFL)
- GSAP standard license (commercial use permitted)
- Firmware libraries with LGPL-2.1 (ESPAsyncWebServer, AsyncTCP) and GPL-3.0 note for LiquidCrystal_I2C
- Font licenses (Fontshare free commercial, Google Fonts SIL OFL)

---

## Remaining Questions

| Question | Status |
|----------|--------|
| Legal entity for copyright holder | ❌ Pending - Individual vs "Antares Laboratory" |
| CLA for external contributors | ❌ Not yet implemented |
| GSAP commercial use verification | ✅ Standard license permits commercial use |
| GSAP bonus plugins used | ❌ Not used (only core GSAP + ScrollTrigger) |
| LiquidCrystal_I2C exact license | ⚠️ Verify specific variant (some GPL-3.0) |
| Hardware license (when files added) | 📋 Future - CERN-OHL-P v2 recommended |
| Git history sanitization | ⏳ Pending - `git filter-repo` before public push |

---

## Verification Checklist

- [x] Root `LICENSE` file created (Apache-2.0)
- [x] `NOTICE` file created with attributions
- [x] Restrictive `LICENSE.txt` removed from installer assets
- [x] Installer config updated to reference root `LICENSE`
- [x] SPDX headers added to project-owned source files
- [x] `README.md` License section updated
- [x] `docs/specs/license-audit.md` updated
- [x] `NOTICE` file created with required attributions
- [ ] Copyright owner confirmation (OWNER_REVIEW_REQUIRED)
- [ ] CLA/Contributor agreement for external contributions
- [ ] Git history sanitization before public push
- [ ] GSAP license verification (core library only - confirmed)

---

*Last updated: 2026-09-27*
*Status: Phase 5B implementation complete, pending human decisions on ownership and git history sanitization*