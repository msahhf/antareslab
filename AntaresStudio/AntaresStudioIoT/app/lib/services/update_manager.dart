/// AntaresStudio IoT - UpdateManager
///
/// GitHub Releases'dan firmware indirme ve ESP32-CAM'e OTA gönderme.
///
/// Akış:
///   1. GitHub API ile son release'ı kontrol et
///   2. .bin (ESP32) ve .hex (Arduino) dosyalarını indir
///   3. ESP32-CAM'e HTTP POST ile firmware gönder
///      - ESP32 firmware → /api/ota/esp32
///      - Arduino firmware → /api/ota/arduino (UART Bridge üzerinden)
///
/// Kullanım:
/// ```dart
/// final manager = UpdateManager(
///   githubRepo: 'AntaresLab/AntaresStudioIoT',
///   espHost: 'antares-scanner.local',
/// );
///
/// final update = await manager.checkForUpdates();
/// if (update.hasUpdate) {
///   await manager.updateESP32(update.espFirmware!);
///   await manager.updateArduino(update.arduinoFirmware!);
/// }
/// ```

import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'dart:convert';

// ============================================================
// Veri Modelleri
// ============================================================

/// GitHub Release bilgisi
class FirmwareRelease {
  final String tagName;
  final String name;
  final String body;
  final DateTime publishedAt;
  final FirmwareAsset? espFirmware;
  final FirmwareAsset? arduinoFirmware;
  final bool hasUpdate;

  FirmwareRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.publishedAt,
    this.espFirmware,
    this.arduinoFirmware,
    this.hasUpdate = false,
  });

  factory FirmwareRelease.fromGitHub(Map<String, dynamic> json) {
    final assets = (json['assets'] as List<dynamic>?) ?? [];

    FirmwareAsset? espAsset;
    FirmwareAsset? arduinoAsset;

    for (final asset in assets) {
      final name = asset['name'] as String;
      if (name.endsWith('.bin')) {
        espAsset = FirmwareAsset.fromGitHub(asset, FirmwareType.esp32);
      } else if (name.endsWith('.hex')) {
        arduinoAsset = FirmwareAsset.fromGitHub(asset, FirmwareType.arduino);
      }
    }

    return FirmwareRelease(
      tagName: json['tag_name'] ?? '',
      name: json['name'] ?? '',
      body: json['body'] ?? '',
      publishedAt: DateTime.parse(json['published_at'] ?? DateTime.now().toIso8601String()),
      espFirmware: espAsset,
      arduinoFirmware: arduinoAsset,
      hasUpdate: espAsset != null || arduinoAsset != null,
    );
  }
}

/// Firmware dosya bilgisi
class FirmwareAsset {
  final String name;
  final String downloadUrl;
  final int sizeBytes;
  final FirmwareType type;

  FirmwareAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.type,
  });

  factory FirmwareAsset.fromGitHub(Map<String, dynamic> json, FirmwareType type) {
    return FirmwareAsset(
      name: json['name'] ?? '',
      downloadUrl: json['browser_download_url'] ?? '',
      sizeBytes: json['size'] ?? 0,
      type: type,
    );
  }

  String get sizeMB => (sizeBytes / (1024 * 1024)).toStringAsFixed(2);
}

enum FirmwareType { esp32, arduino }

/// Güncelleme durumu
enum UpdateStatus {
  idle,
  checking,
  downloading,
  uploading,
  completed,
  error,
}

/// İlerleme bilgisi
class UpdateProgress {
  final UpdateStatus status;
  final double progress; // 0.0 - 1.0
  final String message;
  final String? error;

  UpdateProgress({
    required this.status,
    this.progress = 0.0,
    this.message = '',
    this.error,
  });

  int get percentage => (progress * 100).round();

  @override
  String toString() => '[$status] $percentage% - $message';
}

// ============================================================
// UpdateManager Ana Sınıf
// ============================================================

class UpdateManager {
  /// GitHub repo (owner/repo formatında)
  final String githubRepo;

  /// ESP32-CAM IP/hostname
  final String espHost;

  /// Mevcut ESP32 firmware versiyonu (karşılaştırma için)
  String? currentEspVersion;

  /// Mevcut Arduino firmware versiyonu
  String? currentArduinoVersion;

  /// İlerleme callback'i
  final void Function(UpdateProgress)? onProgress;

  /// HTTP client
  final http.Client _client;

  UpdateManager({
    required this.githubRepo,
    required this.espHost,
    this.currentEspVersion,
    this.currentArduinoVersion,
    this.onProgress,
    http.Client? client,
  }) : _client = client ?? http.Client();

  // --------------------------------------------------------
  // 1. GitHub'dan Son Güncellemeyi Kontrol Et
  // --------------------------------------------------------

  /// GitHub Releases API'den son release'ı çek.
  Future<FirmwareRelease?> checkForUpdates() async {
    _emitProgress(UpdateProgress(
      status: UpdateStatus.checking,
      message: 'GitHub son sürüm kontrol ediliyor...',
    ));

    try {
      final url = 'https://api.github.com/repos/$githubRepo/releases/latest';
      final response = await _client.get(
        Uri.parse(url),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final release = FirmwareRelease.fromGitHub(json);

        // Versiyon karşılaştırma
        final hasESPUpdate = release.espFirmware != null &&
            currentEspVersion != null &&
            release.tagName != currentEspVersion;

        final hasArduinoUpdate = release.arduinoFirmware != null;

        _emitProgress(UpdateProgress(
          status: UpdateStatus.idle,
          message: hasESPUpdate || hasArduinoUpdate
              ? 'Güncelleme mevcut: ${release.tagName}'
              : 'Güncel sürümdesiniz.',
        ));

        return release;
      } else if (response.statusCode == 404) {
        _emitProgress(UpdateProgress(
          status: UpdateStatus.idle,
          message: 'Henüz release yayınlanmamış.',
        ));
        return null;
      } else {
        throw Exception('GitHub API hatası: ${response.statusCode}');
      }
    } catch (e) {
      _emitProgress(UpdateProgress(
        status: UpdateStatus.error,
        error: 'Güncelleme kontrolü başarısız: $e',
      ));
      return null;
    }
  }

  // --------------------------------------------------------
  // 2. Firmware İndir
  // --------------------------------------------------------

  /// GitHub'dan firmware dosyasını indir.
  Future<Uint8List?> downloadFirmware(FirmwareAsset asset) async {
    _emitProgress(UpdateProgress(
      status: UpdateStatus.downloading,
      message: '${asset.name} indiriliyor (${asset.sizeMB} MB)...',
    ));

    try {
      final request = http.Request('GET', Uri.parse(asset.downloadUrl));
      final streamedResponse = await _client.send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception('İndirme hatası: ${streamedResponse.statusCode}');
      }

      final totalBytes = streamedResponse.contentLength ?? asset.sizeBytes;
      final bytes = <int>[];
      int receivedBytes = 0;

      await for (final chunk in streamedResponse.stream) {
        bytes.addAll(chunk);
        receivedBytes += chunk.length;

        _emitProgress(UpdateProgress(
          status: UpdateStatus.downloading,
          progress: totalBytes > 0 ? receivedBytes / totalBytes : 0,
          message: '${asset.name}: ${(receivedBytes / 1024).toStringAsFixed(0)} KB / '
              '${(totalBytes / 1024).toStringAsFixed(0)} KB',
        ));
      }

      final data = Uint8List.fromList(bytes);

      _emitProgress(UpdateProgress(
        status: UpdateStatus.downloading,
        progress: 1.0,
        message: '${asset.name} indirildi (${data.length} bytes)',
      ));

      return data;
    } catch (e) {
      _emitProgress(UpdateProgress(
        status: UpdateStatus.error,
        error: 'İndirme hatası: $e',
      ));
      return null;
    }
  }

  // --------------------------------------------------------
  // 3. ESP32-CAM'e Firmware Gönder (OTA)
  // --------------------------------------------------------

  /// ESP32-CAM'in kendi firmware'ini güncelle.
  Future<bool> updateESP32(FirmwareAsset asset) async {
    // Firmware'i indir
    final firmwareData = await downloadFirmware(asset);
    if (firmwareData == null) return false;

    _emitProgress(UpdateProgress(
      status: UpdateStatus.uploading,
      message: 'ESP32 firmware gönderiliyor...',
    ));

    try {
      final url = 'http://$espHost/api/ota/esp32';
      final request = http.MultipartRequest('POST', Uri.parse(url));
      request.files.add(http.MultipartFile.fromBytes(
        'firmware',
        firmwareData,
        filename: asset.name,
      ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        _emitProgress(UpdateProgress(
          status: UpdateStatus.completed,
          progress: 1.0,
          message: 'ESP32 güncelleme başarılı! Cihaz yeniden başlatılıyor...',
        ));
        return body['success'] == true;
      } else {
        throw Exception('ESP32 OTA hatası: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _emitProgress(UpdateProgress(
        status: UpdateStatus.error,
        error: 'ESP32 güncelleme hatası: $e',
      ));
      return false;
    }
  }

  // --------------------------------------------------------
  // 4. Arduino'yu Güncelle (UART Bridge üzerinden)
  // --------------------------------------------------------

  /// Arduino firmware'ini ESP32 UART Bridge üzerinden güncelle.
  ///
  /// Akış:
  ///   1. .hex dosyası indirilir
  ///   2. ESP32'ye HTTP POST ile gönderilir (/api/ota/arduino)
  ///   3. ESP32, Arduino'yu resetler ve UART bridge moduna geçer
  ///   4. Veri UART üzerinden Arduino bootloader'a aktarılır
  ///   5. STK500 protokolü ile firmware yazılır
  Future<bool> updateArduino(FirmwareAsset asset) async {
    // Firmware'i indir
    final firmwareData = await downloadFirmware(asset);
    if (firmwareData == null) return false;

    _emitProgress(UpdateProgress(
      status: UpdateStatus.uploading,
      message: 'Arduino firmware gönderiliyor (UART Bridge)...',
    ));

    try {
      final url = 'http://$espHost/api/ota/arduino';
      final request = http.MultipartRequest('POST', Uri.parse(url));
      request.files.add(http.MultipartFile.fromBytes(
        'firmware',
        firmwareData,
        filename: asset.name,
      ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        _emitProgress(UpdateProgress(
          status: UpdateStatus.completed,
          progress: 1.0,
          message: 'Arduino güncelleme başarılı!',
        ));
        return body['success'] == true;
      } else {
        throw Exception('Arduino OTA hatası: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _emitProgress(UpdateProgress(
        status: UpdateStatus.error,
        error: 'Arduino güncelleme hatası: $e',
      ));
      return false;
    }
  }

  // --------------------------------------------------------
  // 5. ESP32-CAM Durum Sorgulama
  // --------------------------------------------------------

  /// ESP32-CAM'in mevcut durumunu sorgula.
  Future<Map<String, dynamic>?> getDeviceStatus() async {
    try {
      final url = 'http://$espHost/api/status';
      final response = await _client.get(Uri.parse(url));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('Cihaz durumu alınamadı: $e');
    }
    return null;
  }

  // --------------------------------------------------------
  // 6. Tam Güncelleme İş Akışı
  // --------------------------------------------------------

  /// Her iki cihazı da tek seferde güncelle.
  Future<Map<String, bool>> updateAll() async {
    final results = <String, bool>{};

    // 1. Güncelleme kontrol
    final release = await checkForUpdates();
    if (release == null || !release.hasUpdate) {
      return {'esp32': false, 'arduino': false};
    }

    // 2. ESP32 güncelle
    if (release.espFirmware != null) {
      results['esp32'] = await updateESP32(release.espFirmware!);

      // ESP32 yeniden başladıktan sonra bekle
      if (results['esp32'] == true) {
        _emitProgress(UpdateProgress(
          status: UpdateStatus.uploading,
          message: 'ESP32 yeniden başlatılıyor, 10 saniye bekleniyor...',
        ));
        await Future.delayed(const Duration(seconds: 10));
      }
    }

    // 3. Arduino güncelle (ESP32 hazır olduktan sonra)
    if (release.arduinoFirmware != null) {
      results['arduino'] = await updateArduino(release.arduinoFirmware!);
    }

    return results;
  }

  // --------------------------------------------------------
  // Yardımcı
  // --------------------------------------------------------

  void _emitProgress(UpdateProgress progress) {
    onProgress?.call(progress);
  }

  void dispose() {
    _client.close();
  }
}
