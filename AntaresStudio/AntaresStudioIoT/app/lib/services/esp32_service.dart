/// AntaresStudio IoT - ESP32 HTTP API İstemcisi v2.1
///
/// ESP32-CAM'in AP modunda sunduğu REST API'ye erişim.
/// Sabit IP: 192.168.4.1 (AP gateway)
///
/// v2.1 Değişiklikler:
///   [1] /api/camera/settings POST desteği (NVS kalıcı kamera ayarları)
///   [2] ESP32Status — sd_errors, jpeg_quality, stabilization_ms
///   [3] Motor komutları için uzun timeout (15sn)
///   [4] Hata detaylandırma (timeout vs connection refused)

import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// SD karttaki fotoğraf bilgisi
class SDPhoto {
  final String name;
  final int size;

  SDPhoto({required this.name, required this.size});

  factory SDPhoto.fromJson(Map<String, dynamic> json) {
    return SDPhoto(
      name: json['name'] ?? '',
      size: json['size'] ?? 0,
    );
  }

  String get sizeMB => (size / (1024 * 1024)).toStringAsFixed(2);
  String get sizeKB => (size / 1024).toStringAsFixed(0);
}

/// Arduino komut yanıtı - ENHANCED with BUSY handling
class ArduinoCommandResult {
  final bool success;
  final String response;
  final String command;
  final bool isBusy;  // NEW: Indicates system is in operation
  final bool isTimeout;

  ArduinoCommandResult({
    required this.success,
    required this.response,
    required this.command,
    this.isBusy = false,
    this.isTimeout = false,
  });

  factory ArduinoCommandResult.fromJson(Map<String, dynamic> json) {
    final resp = json['response']?.toString() ?? '';
    final isBusy = resp == 'BUSY';
    final isTimeout = json['timeout'] == true;
    
    return ArduinoCommandResult(
      success: json['success'] == true && !isBusy,
      response: resp,
      command: json['cmd']?.toString() ?? '',
      isBusy: isBusy,
      isTimeout: isTimeout,
    );
  }

  /// Create from a direct response string (for legacy parsing)
  factory ArduinoCommandResult.fromResponse(String response, String cmd) {
    final isBusy = response == 'BUSY';
    final isSuccess = response.startsWith('OK');
    
    return ArduinoCommandResult(
      success: isSuccess && !isBusy,
      response: response,
      command: cmd,
      isBusy: isBusy,
    );
  }
}

/// Black Box (Kara Kutu) command result — v3.2
class BlackBoxCommandResult {
  final bool success;
  final String message;
  final bool isRecording;
  final bool fileDeleted;

  BlackBoxCommandResult({
    required this.success,
    required this.message,
    this.isRecording = false,
    this.fileDeleted = false,
  });

  factory BlackBoxCommandResult.fromJson(Map<String, dynamic> json) {
    return BlackBoxCommandResult(
      success: json['success'] ?? false,
      message: json['message']?.toString() ?? '',
      isRecording: json['is_recording'] ?? false,
      fileDeleted: json['file_deleted'] ?? false,
    );
  }
}

/// ESP32 durum bilgisi — [v3.0]
class ESP32Status {
  final String version;
  final int heapFree;
  final int wifiClients;
  final ArduinoSensorData arduino;
  final CameraSettings camera;
  final bool sdActive;

  ESP32Status({
    required this.version,
    required this.heapFree,
    required this.wifiClients,
    required this.arduino,
    required this.camera,
    required this.sdActive,
  });

  factory ESP32Status.fromJson(Map<String, dynamic> json) {
    return ESP32Status(
      version: json['version'] ?? '3.0.0',
      heapFree: json['heap'] ?? 0,
      wifiClients: json['wifi_clients'] ?? 0,
      arduino: ArduinoSensorData.fromJson(json['arduino'] ?? {}),
      camera: CameraSettings.fromJson(json['camera'] ?? {}),
      sdActive: json['sd_active'] ?? false,
    );
  }
}

/// Arduino sensör verileri — v3.2 with Black Box support
class ArduinoSensorData {
  final double temperature;
  final int humidity;
  final int soilMoisture;
  final int heaterPower;
  final bool fanSly;
  final bool fanDz;
  final String mode;
  final int motorPosition;
  final bool isHomed;
  final bool isRecording;  // [v3.2] Black Box recording flag

  ArduinoSensorData({
    this.temperature = 0,
    this.humidity = 0,
    this.soilMoisture = 0,
    this.heaterPower = 0,
    this.fanSly = false,
    this.fanDz = false,
    this.mode = 'OTONOM',
    this.motorPosition = 0,
    this.isHomed = false,
    this.isRecording = false,  // [v3.2]
  });

  factory ArduinoSensorData.fromJson(Map<String, dynamic> json) {
    // Handle both string and numeric types safely
    dynamic parseValue(dynamic val, dynamic defaultVal) {
      if (val == null) return defaultVal;
      if (val is num) return val;
      if (val is String) {
        if (defaultVal is int) return int.tryParse(val) ?? defaultVal;
        if (defaultVal is double) return double.tryParse(val) ?? defaultVal;
        if (defaultVal is bool) {
          return val == '1' || val.toLowerCase() == 'true';
        }
      }
      return defaultVal;
    }

    return ArduinoSensorData(
      temperature: parseValue(json['temp'], 0.0),
      humidity: parseValue(json['hum'], 0),
      soilMoisture: parseValue(json['soil'], 0),
      heaterPower: parseValue(json['heater'], 0),
      fanSly: parseValue(json['fanSly'], false),
      fanDz: parseValue(json['fanDz'], false),
      mode: json['mode']?.toString() ?? 'OTONOM',
      motorPosition: parseValue(json['position'], 0),
      isHomed: parseValue(json['homed'], false),
      isRecording: parseValue(json['is_record'], false),  // [v3.2]
    );
  }
}

/// [1] Kamera ayarları modeli
class CameraSettings {
  final int quality;       // 0-63 (düşük = yüksek kalite)
  final int frameSize;     // 0-13 (13 = UXGA 1600x1200)
  final int stabilizationMs;
  final int warmupFrames;

  CameraSettings({
    this.quality = 10,
    this.frameSize = 13,
    this.stabilizationMs = 800,
    this.warmupFrames = 3,
  });

  Map<String, dynamic> toJson() => {
    'quality': quality,
    'framesize': frameSize,
    'stabilization_ms': stabilizationMs,
    'warmup_frames': warmupFrames,
  };

  factory CameraSettings.fromJson(Map<String, dynamic> json) {
    return CameraSettings(
      quality: json['quality'] ?? 10,
      frameSize: json['framesize'] ?? 13,
      stabilizationMs: json['stabilization_ms'] ?? 800,
      warmupFrames: json['warmup_frames'] ?? 3,
    );
  }

  /// İnsan-okunabilir çözünürlük adı
  String get resolutionName {
    switch (frameSize) {
      case 13: return 'UXGA (1600×1200)';
      case 12: return 'SXGA (1280×1024)';
      case 10: return 'XGA (1024×768)';
      case 8:  return 'SVGA (800×600)';
      case 5:  return 'CIF (400×296)';
      default: return 'Mode $frameSize';
    }
  }
}

/// ESP32-CAM HTTP API İstemcisi
class ESP32Service {
  static const String _baseUrl = 'http://192.168.4.1';
  static const String _streamUrl = 'http://192.168.4.1:81';
  static const Duration _timeout = Duration(seconds: 5);
  static const Duration _captureTimeout = Duration(seconds: 10);
  static const Duration _motorTimeout = Duration(seconds: 20);   // [3]

  final http.Client _client;

  ESP32Service({http.Client? client}) : _client = client ?? http.Client();

  // ---- Durum ----

  /// ESP32 durum bilgisi
  Future<ESP32Status?> getStatus() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/status'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return ESP32Status.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  /// Arduino sensör verilerini (Status içinden veya direkt)
  Future<ArduinoSensorData?> getArduinoStatus() async {
    final status = await getStatus();
    return status?.arduino;
  }

  /// Bağlantı kontrolü
  Future<bool> ping() async {
    final status = await getStatus();
    return status != null;
  }

  // ---- Kamera ----

  /// Tek fotoğraf çek (JPEG döner, SD'ye kaydetmez)
  Future<Uint8List?> capturePhoto() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/capture'))
          .timeout(_captureTimeout);
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  /// MJPEG stream URL'i
  String get streamUrl => '$_streamUrl/api/stream';

  /// [1] Kamera ayarlarını güncelle (NVS'ye kaydedilir)
  Future<CameraSettings?> updateCameraSettings(CameraSettings settings) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/api/camera/settings'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(settings.toJson()),
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['success'] == true) {
          return CameraSettings.fromJson(json);
        }
      }
    } catch (_) {}
    return null;
  }

  /// [1] Mevcut kamera ayarlarını oku (ESP32 status'tan)
  Future<CameraSettings?> getCameraSettings() async {
    final status = await getStatus();
    if (status == null) return null;
    return status.camera;
  }

  // ---- Arduino Komut ----

  /// Arduino'ya komut gönder
  Future<ArduinoCommandResult?> sendArduinoCommand(String cmd) async {
    try {
      // [3] Motor komutları için uzun timeout
      final isMotorCmd = cmd.startsWith('R') || cmd.startsWith('H') || cmd.startsWith('T');
      final timeout = isMotorCmd ? _motorTimeout : const Duration(seconds: 10);

      final response = await _client
          .post(
            Uri.parse('$_baseUrl/api/arduino/command'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'cmd': cmd}),
          )
          .timeout(timeout);
          
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        
        // Handle BUSY response from Arduino
        final resp = json['response']?.toString() ?? '';
        if (resp == 'BUSY') {
          return ArduinoCommandResult(
            success: false,
            response: 'BUSY',
            command: cmd,
            isBusy: true,
            isTimeout: false,
          );
        }
        
        return ArduinoCommandResult.fromJson(json);
      }
    } catch (e) {
      debugPrint('[ESP32Service] Command error: $e');
    }
    return null;
  }

  /// Motor Home
  Future<bool> motorHome() async {
    final result = await sendArduinoCommand('H');
    return result?.success ?? false;
  }

  /// Belirli açıya dön
  Future<bool> motorRotate(double angle) async {
    final result = await sendArduinoCommand('R,${angle.toStringAsFixed(1)}');
    return result?.success ?? false;
  }

  /// Motor etkinleştir/devre dışı
  Future<bool> motorEnable(bool enable) async {
    final result = await sendArduinoCommand(enable ? 'E' : 'D');
    return result?.success ?? false;
  }

  /// Otonom modu duraklat (Studio bağlandı)
  Future<bool> pauseAutonomous() async {
    final result = await sendArduinoCommand('P');
    return result?.success ?? false;
  }

  /// Otonom moda devam et (Studio ayrıldı)
  Future<bool> resumeAutonomous() async {
    final result = await sendArduinoCommand('C');
    return result?.success ?? false;
  }

  // ---- Black Box (Kara Kutu) v3.2 ----

  /// Send START/STOP command to Black Box endpoint
  Future<BlackBoxCommandResult?> sendBlackBoxCommand(String action) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/blackbox/${action.toLowerCase()}'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 60)); // Long timeout for STOP + upload

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return BlackBoxCommandResult.fromJson(json);
      }
    } catch (e) {
      debugPrint('[ESP32Service] BlackBox command error: $e');
    }
    return null;
  }

  /// Get Black Box status from ESP32
  Future<Map<String, dynamic>?> getBlackBoxStatus() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/blackbox/status'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('[ESP32Service] BlackBox status error: $e');
    }
    return null;
  }

  // ---- SD Kart (V3.0: Kaldırıldı - High Speed Direct Transfer Kullanın) ----

  // ---- OTA Firmware ----

  /// ESP32 firmware güncelleme
  Future<bool> uploadESPFirmware(Uint8List data) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/ota/esp32'),
      );
      request.files.add(http.MultipartFile.fromBytes(
        'firmware',
        data,
        filename: 'firmware.bin',
      ));
      final streamed = await request.send().timeout(const Duration(minutes: 5));
      return streamed.statusCode == 200;
    } catch (_) {}
    return false;
  }

  /// Arduino firmware güncelleme (UART Bridge üzerinden)
  Future<bool> uploadArduinoFirmware(Uint8List data) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/ota/arduino'),
      );
      request.files.add(http.MultipartFile.fromBytes(
        'firmware',
        data,
        filename: 'firmware.hex',
      ));
      final streamed = await request.send().timeout(const Duration(minutes: 5));
      return streamed.statusCode == 200;
    } catch (_) {}
    return false;
  }

  void dispose() {
    _client.close();
  }
}
