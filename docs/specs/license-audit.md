# License Audit

## Current License Status

### Repository License

**No LICENSE file committed.** The repository contains a restrictive license template at:
- `services/photogrammetry-api/setup_prep/assets/LICENSE.txt` — "All rights reserved", prohibits copying/distribution/reverse engineering

### Third-Party Dependencies

#### Flutter App (`apps/desktop/pubspec.yaml`)

| Package | Version | License |
|---------|---------|---------|
| flutter | SDK | BSD-3-Clause |
| http | ^1.2.0 | BSD-3-Clause |
| provider | ^6.1.0 | MIT |
| path_provider | ^2.1.0 | BSD-3-Clause |
| cupertino_icons | ^1.0.6 | MIT |
| url_launcher | ^6.2.0 | BSD-3-Clause |
| flutter_lints | ^3.0.0 | BSD-3-Clause |

**All Flutter dependencies: BSD-3-Clause or MIT (permissive)**

#### Python Backend (`services/photogrammetry-api/requirements.txt`)

| Package | Version | License |
|---------|---------|---------|
| fastapi | >=0.109.0 | MIT |
| uvicorn[standard] | >=0.27.0 | BSD-3-Clause |
| python-multipart | >=0.0.9 | MIT |
| rembg | >=2.0.50 | MIT |
| Pillow | >=10.2.0 | HPND (MIT-like) |
| numpy | >=1.26.0 | BSD-3-Clause |
| trimesh | >=4.0.0 | MIT |
| pyglet | >=2.0.0 | BSD-3-Clause |
| pydantic | >=2.5.0 | MIT |
| pydantic-settings | >=2.0.0 | MIT |
| aiofiles | >=23.2.0 | Apache-2.0 |
| python-dotenv | >=1.0.0 | MIT |
| httpx | >=0.27.0 | BSD-3-Clause |

**All Python dependencies: MIT, BSD-3-Clause, or Apache-2.0 (permissive)**

#### Documentation Portal (`web/docs/package.json`)

| Package | Version | License |
|---------|---------|---------|
| react | ^19.2.0 | MIT |
| react-dom | ^19.2.0 | MIT |
| react-router-dom | ^7.13.0 | MIT |
| react-syntax-highlighter | ^16.1.0 | MIT |
| lucide-react | ^0.563.0 | ISC |
| cmdk | ^1.1.1 | MIT |
| tailwindcss | ^4.1.18 | MIT |
| @tailwindcss/vite | ^4.1.18 | MIT |
| vite | ^7.2.4 | MIT |
| eslint | ^9.39.1 | MIT |
| globals | ^16.5.0 | MIT |

**All Node.js dependencies: MIT or ISC (permissive)**

#### Firmware (PlatformIO Libraries)

| Library | License |
|---------|---------|
| ArduinoJson | MIT |
| ESPAsyncWebServer | LGPL-2.1 |
| AsyncTCP | LGPL-2.1 |
| SD_MMC | LGPL-2.1 (part of ESP32 Arduino core) |
| LiquidCrystal_I2C | GPL-3.0 or custom |
| DHT sensor library | MIT |

**Note:** ESPAsyncWebServer/AsyncTCP are LGPL-2.1 — may require dynamic linking consideration for static firmware.

---

## Existing Restrictive License

`services/photogrammetry-api/setup_prep/assets/LICENSE.txt` contains:

> "All rights reserved. Unauthorized copying, distribution, or reverse engineering is prohibited."

This is **incompatible** with open source distribution and conflicts with permissive dependencies.

---

## License Options Comparison

| Criterion | MIT | Apache-2.0 | GPL-3.0 |
|-----------|-----|------------|---------|
| **Permissiveness** | Maximum | High (patent grant) | Copyleft |
| **Commercial Use** | ✅ | ✅ | ✅ (with source) |
| **Modification** | ✅ | ✅ | ✅ (must share) |
| **Distribution** | ✅ | ✅ | ✅ (must share) |
| **Patent Grant** | ❌ | ✅ | ✅ |
| **Private Use** | ✅ | ✅ | ✅ |
| **License Compatibility** | All | All | GPL-compatible only |
| **LGPL Dependency Issue** | ✅ OK | ✅ OK | ❌ Conflict |
| **Hardware/Firmware Suitability** | ✅ Best | ✅ Good | ⚠️ Complex |

### Key Considerations

1. **LGPL Dependencies** (ESPAsyncWebServer, AsyncTCP, SD_MMC): MIT and Apache-2.0 allow static linking with LGPL; GPL-3.0 creates conflict.

2. **Hardware/Firmware Distribution**: MIT/Apache-2.0 allow binary-only firmware distribution; GPL-3.0 requires source provision.

3. **Commercial Adoption**: MIT/Apache-2.0 maximize adoption; GPL-3.0 may deter commercial users.

4. **Patent Protection**: Apache-2.0 provides explicit patent grant; MIT does not.

5. **Existing Restrictive License**: Must be replaced before any open source release.

---

## Recommendation

**Primary: Apache-2.0**
- Explicit patent grant (valuable for hardware/imaging patents)
- Compatible with all current dependencies (MIT, BSD, LGPL, Apache)
- Industry standard for hardware/software projects
- Clear commercial-friendly terms

**Alternative: MIT**
- Simplest, maximum permissiveness
- No patent grant (risk if patents exist)
- Compatible with all dependencies

**Not Recommended: GPL-3.0**
- Incompatible with LGPL dependencies (static linking issue)
- Copyleft may deter commercial/industrial adoption
- Complex for firmware binary distribution

---

## Required Actions Before Release

1. **Remove** `services/photogrammetry-api/setup_prep/assets/LICENSE.txt`
2. **Add** root `LICENSE` file with chosen license text
3. **Update** `CONTRIBUTING.md` with license header requirement
4. **Add** license headers to source files (SPDX identifiers)
4. **Verify** all third-party licenses still compatible
5. **Document** license in README

---

## License Header Template (SPDX)

```cpp
// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 AntaresLab Contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
```

---

## Decision Required

**Project owner must select license** before public release. This audit provides data for informed decision.