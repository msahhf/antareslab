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

/// Arduino komut yanıtı
class ArduinoCommandResult {
  final bool success;
  final String response;
  final String command;

  ArduinoCommandResult({
    required this.success,
    required this.response,
    required this.command,
  });

  factory ArduinoCommandResult.fromJson(Map<String, dynamic> json) {
    return ArduinoCommandResult(
      success: json['success'] ?? false,
      response: json['response'] ?? '',
      command: json['cmd'] ?? '',
    );
  }
}

/// ESP32 durum bilgisi — [2] genişletilmiş
class ESP32Status {
  final String firmware;
  final String ip;
  final int clients;
  final bool bridgeMode;
  final bool sdCard;
  final int sdErrors;          // [2] SD ardışık hata sayısı
  final int heapFree;
  final int psramFree;
  final int uptimeSec;
  final int jpegQuality;       // [1] Kamera kalitesi (0-63)
  final int frameSize;         // [1] Kamera çözünürlüğü
  final int stabilizationMs;   // [1] Motor stabilizasyon süresi

  ESP32Status({
    required this.firmware,
    required this.ip,
    required this.clients,
    required this.bridgeMode,
    required this.sdCard,
    this.sdErrors = 0,
    required this.heapFree,
    required this.psramFree,
    required this.uptimeSec,
    this.jpegQuality = 10,
    this.frameSize = 13,
    this.stabilizationMs = 800,
  });

  factory ESP32Status.fromJson(Map<String, dynamic> json) {
    return ESP32Status(
      firmware: json['firmware'] ?? '--',
      ip: json['ip'] ?? '192.168.4.1',
      clients: json['clients'] ?? 0,
      bridgeMode: json['bridge_mode'] ?? false,
      sdCard: json['sd_card'] ?? false,
      sdErrors: json['sd_errors'] ?? 0,
      heapFree: json['heap_free'] ?? 0,
      psramFree: json['psram_free'] ?? 0,
      uptimeSec: json['uptime_sec'] ?? 0,
      jpegQuality: json['jpeg_quality'] ?? 10,
      frameSize: json['frame_size'] ?? 13,
      stabilizationMs: json['stabilization_ms'] ?? 800,
    );
  }

  bool get sdHealthy => sdCard && sdErrors == 0;
}

/// Arduino sensör verileri
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
  });

  factory ArduinoSensorData.fromJson(Map<String, dynamic> json) {
    return ArduinoSensorData(
      temperature: double.tryParse(json['temp']?.toString() ?? '0') ?? 0,
      humidity: int.tryParse(json['hum']?.toString() ?? '0') ?? 0,
      soilMoisture: int.tryParse(json['soil']?.toString() ?? '0') ?? 0,
      heaterPower: int.tryParse(json['heater']?.toString() ?? '0') ?? 0,
      fanSly: json['fanSly']?.toString() == '1',
      fanDz: json['fanDz']?.toString() == '1',
      mode: json['mode'] ?? 'OTONOM',
      motorPosition: int.tryParse(json['position']?.toString() ?? '0') ?? 0,
      isHomed: json['homed']?.toString() == '1',
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

  /// Arduino sensör verileri
  Future<ArduinoSensorData?> getArduinoStatus() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/arduino/status'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return ArduinoSensorData.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
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
    return CameraSettings(
      quality: status.jpegQuality,
      frameSize: status.frameSize,
      stabilizationMs: status.stabilizationMs,
    );
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
        return ArduinoCommandResult.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
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

  // ---- SD Kart ----

  /// SD karttaki fotoğrafları listele
  Future<List<SDPhoto>> listSDPhotos() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/sd/list'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        // [4] SD hata kontrolü
        if (json.containsKey('error')) {
          print('[ESP32Service] SD Hata: ${json['error']}');
          return [];
        }
        final photos = (json['photos'] as List<dynamic>?) ?? [];
        return photos.map((p) => SDPhoto.fromJson(p)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// SD karttan fotoğraf indir
  Future<Uint8List?> downloadSDPhoto(String name) async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/sd/photo?name=$name'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  /// SD karttan fotoğraf sil
  Future<bool> deleteSDPhoto(String name) async {
    try {
      final response = await _client
          .delete(Uri.parse('$_baseUrl/api/sd/photo?name=$name'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['success'] == true;
      }
    } catch (_) {}
    return false;
  }

  /// Tüm SD fotoğraflarını indir ve sil (toplu aktarım)
  Future<List<Uint8List>> transferAllFromSD({
    void Function(int index, int total, String name)? onProgress,
  }) async {
    final photos = await listSDPhotos();
    final results = <Uint8List>[];

    for (int i = 0; i < photos.length; i++) {
      final photo = photos[i];
      onProgress?.call(i + 1, photos.length, photo.name);

      final data = await downloadSDPhoto(photo.name);
      if (data != null) {
        results.add(data);
        await deleteSDPhoto(photo.name);
      }
    }

    return results;
  }

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
