# Public Information Audit

## Overview

This document records the repository-level checks performed to keep AntaresLab suitable for public documentation and open-source distribution.

It focuses on credentials, personal filesystem information, internal documentation, generated data, legacy content, packaging artifacts, and third-party service references.

---

## 1. Credentials & Secrets

| Location                                          | Type                  | Status                        |
| ------------------------------------------------- | --------------------- | ----------------------------- |
| `firmware/gateway-esp32cam/credentials.h`         | Wi-Fi credentials     | Gitignored; template provided |
| `services/photogrammetry-api/.env`                | Backend configuration | Gitignored; template provided |
| `firmware/gateway-esp32cam/credentials.h.example` | Template only         | ✅ Safe; no real credentials   |
| `services/photogrammetry-api/.env.example`        | Template only         | ✅ Safe; no real credentials   |

**Status:** ✅ Secret-bearing files are excluded from version control, while example files contain placeholders only.

---

## 2. Personal Filesystem Paths

Historical user-specific filesystem paths were identified during repository cleanup and sanitized before the public release.

The active project uses relative paths, environment variables, or runtime discovery where machine-specific paths are required.

**Status:** ✅ No known user-specific filesystem paths remain in the active project configuration.

---

## 3. Personal Identifiers

| Type                       | Location                                       | Status                                   |
| -------------------------- | ---------------------------------------------- | ---------------------------------------- |
| Author identity            | Repository metadata and project documentation  | ✅ Public project identity                |
| Contact email              | `web/landing/index.html`                       | ✅ Intentionally public marketing contact |
| GitHub repository identity | Project links and update/release configuration | ✅ Uses `msahhf/antareslab`               |

**Note:** The landing-page contact address is intentionally published as a project contact channel and is not treated as a secret.

---

## 4. Internal Project References

| Reference                       | Location                              | Public Suitability               |
| ------------------------------- | ------------------------------------- | -------------------------------- |
| `ANTARES_KAPSUL_LAB` Wi-Fi SSID | Firmware and documentation            | ✅ Product/network identifier     |
| `192.168.4.1` / `192.168.4.2`   | Firmware, backend, documentation      | ✅ Local AP/network configuration |
| `ANTARES_STUDIO_IOT`            | Firmware and application code         | ✅ Product identifier             |
| `AntaresStudio`                 | Application, installer, documentation | ✅ Product name                   |

These values describe the intended local system architecture and do not contain personal secrets.

---

## 5. Internal Documentation

| File                     | Content Type                           | Status                                         |
| ------------------------ | -------------------------------------- | ---------------------------------------------- |
| `implementation_plan.md` | Historical architecture plan (Turkish) | 🔒 Internal; exclude from public documentation |

Obsolete internal planning and walkthrough documents were removed before the final public repository state.

Historical phase reports used during repository cleanup were not retained as public project documentation.

---

## 6. Generated & Test Data

The following temporary/generated material was removed during repository cleanup:

| Data Type                                                    | Status    |
| ------------------------------------------------------------ | --------- |
| Test photos (`images/`, `images_raw/`)                       | ✅ Removed |
| Generated 3D output (`output_3d/`)                           | ✅ Removed |
| Analyze/debug outputs (`analyze_output.txt`, `analyze2.txt`) | ✅ Removed |
| Obsolete `*_v3` prototype files                              | ✅ Removed |
| Temporary firmware snippets                                  | ✅ Removed |

No generated test datasets are intentionally included in the active public project tree.

---

## 7. Legacy & Prototype Content

Legacy implementations remain isolated under `archive/` for historical reference and are not part of the active production system.

| Path                                     | Content                                  | Public Status                               |
| ---------------------------------------- | ---------------------------------------- | ------------------------------------------- |
| `archive/legacy-desktop-pyqt/`           | Legacy PyQt6 desktop application         | ⚠️ Archived; not part of active development |
| `archive/legacy-electronics/`            | Legacy electronics/firmware              | ⚠️ Archived; not part of active development |
| `archive/prototypes/web-colmap-backend/` | Previous COLMAP/Open3D backend prototype | ⚠️ Archived prototype                       |
| `archive/prototypes/web-react-frontend/` | Previous React/Vite/Three.js prototype   | ⚠️ Archived prototype                       |
| `archive/legacy-docs/`                   | Historical project documentation         | ⚠️ Archived reference material              |

Archive content is intentionally separated from the current production codebase and should not be presented as the current architecture.

---

## 8. Installer & Build Artifacts

| Path                                                        | Content                                              | Status                     |
| ----------------------------------------------------------- | ---------------------------------------------------- | -------------------------- |
| `services/photogrammetry-api/setup_prep/`                   | Inno Setup configuration and Windows release tooling | ✅ Required release tooling |
| `services/photogrammetry-api/setup_prep/assets/LICENSE.txt` | Former restrictive installer license                 | ✅ Removed                  |

The installer now references the repository's root Apache-2.0 `LICENSE` file.

---

## 9. Third-Party Service & Dependency References

| Service / Dependency | Usage                                       | Public Suitability       |
| -------------------- | ------------------------------------------- | ------------------------ |
| GitHub Releases      | Application and firmware distribution       | ✅ Standard               |
| Vercel               | Web deployment/infrastructure documentation | ✅ Standard               |
| Meshroom             | Photogrammetry processing                   | ✅ Open-source dependency |
| rembg / u2net        | Background removal                          | ✅ Open-source dependency |

Third-party components are documented through the project's `NOTICE` file and dependency manifests where applicable.

---

## 10. Public Release Verification

* [x] Root Apache-2.0 `LICENSE` added
* [x] `NOTICE` file added and maintained
* [x] Restrictive installer license removed
* [x] `.gitignore` covers credentials and generated build artifacts
* [x] Secret-bearing configuration files remain excluded
* [x] Personal filesystem paths sanitized
* [x] Obsolete internal plan files removed
* [x] `SECURITY.md` added
* [x] `CONTRIBUTING.md` added
* [x] Legacy and prototype code isolated under `archive/`
* [x] Public repository references aligned with the current `msahhf/antareslab` repository
* [x] Temporary test/generated data removed

---

## Final Status

**Public repository audit status: ✅ Complete**

The repository is structured for public source distribution with active production code separated from archived material, credentials excluded, restrictive licensing removed, and project ownership/licensing documented at the repository root.
