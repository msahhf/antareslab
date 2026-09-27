# API Reference

Base URL: `http://localhost:8000` (Backend) | `http://192.168.4.1` (ESP32)

All endpoints return JSON unless noted. Errors follow:
```json
{ "success": false, "error": "message", "code": 400 }
```

---

## Backend API (`services/photogrammetry-api/`)

### Health & Info

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Service health + ESP32 registration + Meshroom/rembg status |
| `GET` | `/api/info` | API metadata (endpoints, version) |
| `GET` | `/api/esp32/status` | Network interface + ESP32 registration status |

### Telemetry

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/telemetry` | Latest capsule telemetry (polling) |
| `POST` | `/api/telemetry` | Receive telemetry from ESP32/Flutter |

**GET `/api/telemetry` Response:**
```json
{
  "temperature": 22.5,
  "humidity": 45,
  "soil_moisture": 512,
  "mode": "STANDBY",
  "heater_power": 0,
  "fan_sly": false,
  "fan_dz": false,
  "motor_position": 0,
  "is_homed": false,
  "timestamp": 1700000000.0,
  "age_seconds": 5.2
}
```

---

### Photos API (`/api/v1/photos`)

#### Upload Photo
```http
POST /api/v1/photos/upload
Content-Type: multipart/form-data

file: <JPEG/PNG>
session_id: <optional string>
```

**Response (200):**
```json
{
  "success": true,
  "session_id": "a1b2c3d4",
  "photo_index": 0,
  "filename": "photo_0000.jpg",
  "size_mb": 2.3,
  "total_photos": 1
}
```

**Errors:**
- `400` — Invalid file type (only JPEG/PNG)
- `413` — File > 50 MB
- `400` — Session photo limit (100)

#### Clean Backgrounds (rembg)
```http
POST /api/v1/photos/clean/{session_id}
```

**Response (200):**
```json
{
  "success": true,
  "session_id": "a1b2c3d4",
  "status": "processing",
  "total_photos": 8,
  "message": "Arka plan temizleme başlatıldı. /status ile takip edin."
}
```

#### Session Status
```http
GET /api/v1/photos/status/{session_id}
```

**Response (200):**
```json
{
  "session_id": "a1b2c3d4",
  "created_at": 1700000000.0,
  "photo_count": 8,
  "photos": [
    { "index": 0, "filename": "photo_0000.jpg", "size_bytes": 2400000, "path": "...", "cleaned": true, "cleaned_path": "..." }
  ],
  "cleaning_status": "completed",
  "cleaned_count": 8
}
```

#### Download Cleaned Photo
```http
GET /api/v1/photos/cleaned/{session_id}/{filename}
```
Returns `image/png` file.

---

### Pipeline API (`/api/v1/pipeline`)

#### Start Pipeline
```http
POST /api/v1/pipeline/start/{session_id}?use_cleaned=true
```

**Response (200):**
```json
{
  "success": true,
  "pipeline_id": "p1q2r3s4",
  "session_id": "a1b2c3d4",
  "photo_count": 8,
  "message": "Pipeline başlatıldı. /status/p1q2r3s4 ile takip edin."
}
```

**Parameters:**
- `use_cleaned` (bool, default `true`) — use rembg-cleaned photos

#### Pipeline Status
```http
GET /api/v1/pipeline/status/{pipeline_id}
```

**Response (200):**
```json
{
  "pipeline_id": "p1q2r3s4",
  "session_id": "a1b2c3d4",
  "status": "running",
  "progress": 45,
  "current_step": "Feature Matching",
  "error": null,
  "output_model": null,
  "optimized_model": null,
  "photo_count": 8,
  "started_at": 1700000000.0,
  "completed_at": null,
  "duration_sec": null,
  "cache_cleaned": false
}
```

**Status values:** `queued`, `running`, `completed`, `error`, `cancelled`

#### List Pipelines
```http
GET /api/v1/pipeline/list
```

#### Cancel Pipeline
```http
DELETE /api/v1/pipeline/cancel/{pipeline_id}
```

#### Download Model
```http
GET /api/v1/pipeline/model/{pipeline_id}?optimized=true
```
Returns `model/gltf-binary` (.glb) or `text/plain` (.obj) file.

#### Cleanup Session
```http
POST /api/v1/pipeline/cleanup/{session_id}
```

#### Cleanup All Caches
```http
POST /api/v1/pipeline/cleanup/cache/all
```

#### Disk Usage
```http
GET /api/v1/pipeline/disk-usage
```

**Response:**
```json
{
  "uploads_mb": 45.2,
  "cleaned_mb": 38.1,
  "output_mb": 120.5,
  "cache_mb": 2048.0,
  "models_mb": 15.3,
  "total_mb": 2267.1
}
```

---

### Dashboard Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/` | Static dashboard HTML |
| `GET` | `/dashboard` | Redirect to `/` |
| `GET` | `/api/logs?limit=50` | Recent system logs |

---

## ESP32 API (`http://192.168.4.1`)

### System

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/status` | ESP32 + Arduino status |
| `GET` | `/api/capture` | Capture JPEG (returns `image/jpeg`) |
| `GET` | `/api/stream` | MJPEG live stream |

### Arduino Command Forwarding

```http
POST /api/arduino/command
Content-Type: application/json

{ "cmd": "<COMMAND>" }
```

**Response:**
```json
{
  "cmd": "H",
  "response": "OK,HOMING",
  "success": true,
  "timeout": false
}
```

### Camera Settings

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/camera/settings` | Current quality, framesize, stabilization |
| `POST` | `/api/camera/settings` | Update settings |

**Settings JSON:**
```json
{
  "quality": 10,
  "framesize": 13,
  "stabilization_ms": 800
}
```

### SD Card Sync

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/sync/list` | List session folders |
| `GET` | `/sync/download/{path}` | Download file from SD |

### OTA Updates

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/ota/esp32` | ESP32 firmware upload |
| `POST` | `/api/ota/arduino` | Arduino firmware upload (STK500 bridge) |

---

## Arduino Commands (via ESP32 `/api/arduino/command`)

| Command | Format | Description | Response |
|---------|--------|-------------|----------|
| Home | `H` | Move to home position | `OK,HOMING` |
| Rotate | `R,<angle>` | Rotate to absolute angle | `OK,ROT` |
| Start Scan | `G` | Begin 360° scan (8 shots) | `OK,SCAN_START` |
| Cancel | `X` | Cancel current operation | `OK,CANCEL` |
| Manual Mode | `P` | Enter manual mode | `OK,MANUAL` |
| Auto Mode | `C` | Resume autonomous mode | `OK,AUTO` |
| Enable Motor | `E` | Enable stepper driver | `OK,EN` |
| Disable Motor | `D` | Disable stepper driver | `OK,DIS` |
| Set Speed | `V,<speed>` | Set motor step delay | `OK,SPD` |
| Status | `S` | Request telemetry | `OK,<temp>,<hum>,...` |

### Arduino Autonomous Messages (sent to ESP32)

| Message | Description |
|---------|-------------|
| `CEK` | Capture request (every 5 min in auto) |
| `360_START` | Autonomous scan started |
| `360_END` | Autonomous scan completed |
| `DATA,<temp>,<hum>,<soil>,<heater>,<fanSly>,<fanDz>,<mode>` | Periodic telemetry (1s) |

---

## Error Responses

### Backend (FastAPI)
```json
{ "detail": "Error message" }  // HTTP 4xx/5xx
```

### ESP32 (HTTP)
```json
{ "error": "message", "code": 500, "success": false }
```

### Arduino (UART)
```
BUSY           // System busy (scan/homing), rejects PC commands
ERR,CMD        // Unknown command
ERR,CAP        // Capture failed
ERR,CAP_FAIL   // Camera frame buffer error
OK,CAP         // Capture success
TIMEOUT        // Arduino response timeout
```

---

## CORS

- **Backend**: `allow_origins=["*"]`, `allow_methods=["*"]`, `allow_headers=["*"]`
- **ESP32**: All handlers set `Access-Control-Allow-Origin: *`

---

## Rate Limits

| Endpoint | Limit |
|----------|-------|
| `/api/v1/photos/upload` | No hard limit (size-based) |
| `/api/v1/pipeline/start` | One per session (enforced by session state) |
| `/api/status` (ESP32) | Polling-friendly, no limit |
| `/api/capture` (ESP32) | Hardware-limited (~1 fps) |

---

## WebSocket (Backend)

| Endpoint | Purpose |
|----------|---------|
| `/ws/telemetry` | Real-time telemetry push (planned) |
| `/ws/pipeline/{pid}` | Pipeline progress push (planned) |

> **Note**: WebSocket endpoints defined in `websocket_manager.py` but not fully integrated in current version.