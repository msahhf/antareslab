/// AntaresStudio IoT - Backend Süreç Yöneticisi
///
/// Flutter uygulaması açıldığında Python backend'i (antares_backend.exe)
/// gizli pencere olarak başlatır, kapandığında temiz şekilde sonlandırır.
///
/// Dosya yapısı (kurulum sonrası):
///   C:\Program Files\AntaresStudio\
///   ├── apps\desktop\                 ← Flutter exe + dll'ler
///   │   └── antares_studio_iot.exe
///   └── services\photogrammetry-api\  ← PyInstaller çıktısı
///       └── antares_backend.exe

import 'dart:io';
import 'package:flutter/foundation.dart';

class BackendProcessManager {
  Process? _backendProcess;
  bool _isRunning = false;
  int? _pid;

  bool get isRunning => _isRunning;
  int? get pid => _pid;

  /// Backend exe'nin bağıl konumunu bul
  String _resolveBackendPath() {
    // Flutter exe konumu: .../apps/desktop/antares_studio_iot.exe
    // Backend konumu:     .../services/photogrammetry-api/antares_backend.exe
    final exeDir = File(Platform.resolvedExecutable).parent.path;

    // Release kurulum yapısı: exe apps/desktop/ altında, backend ../services/photogrammetry-api/ altında
    final backendPath = '$exeDir\\..\\services\\photogrammetry-api\\antares_backend.exe';
    final normalizedPath = File(backendPath).absolute.path;

    // Geliştirme ortamında doğrudan backend dizini kontrol
    if (!File(normalizedPath).existsSync()) {
      // Debug: proje kökünden bağıl yol
      // apps/desktop/build/windows/x64/runner/Release -> services/photogrammetry-api
      final debugPath = '$exeDir\\..\\..\\..\\..\\..\\services\\photogrammetry-api\\antares_backend.exe';
      if (File(debugPath).existsSync()) {
        return File(debugPath).absolute.path;
      }
    }

    return normalizedPath;
  }

  /// Backend'i gizli pencere olarak başlat
  Future<bool> startBackend() async {
    if (_isRunning) {
      debugPrint('[Backend] Zaten çalışıyor (PID: $_pid)');
      return true;
    }

    final backendExe = _resolveBackendPath();

    if (!File(backendExe).existsSync()) {
      debugPrint('[Backend] EXE bulunamadı: $backendExe');
      debugPrint('[Backend] Backend servisi başlatılmadı — geliştirme modunda manuel başlatın.');
      return false;
    }

    try {
      debugPrint('[Backend] Başlatılıyor: $backendExe');

      _backendProcess = await Process.start(
        backendExe,
        [],
        mode: ProcessStartMode.detached,       // Gizli pencere, bağımsız süreç
        workingDirectory: File(backendExe).parent.path,
      );

      _pid = _backendProcess!.pid;
      _isRunning = true;

      debugPrint('[Backend] Başlatıldı (PID: $_pid)');

      // Backend'in ayağa kalkmasını bekle (max 10sn)
      await _waitForBackendReady();

      return true;
    } catch (e) {
      debugPrint('[Backend] Başlatma hatası: $e');
      return false;
    }
  }

  /// Backend'in HTTP API'sine bağlanabilene kadar bekle
  Future<bool> _waitForBackendReady() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);

    for (int i = 0; i < 10; i++) {
      try {
        final request = await client.getUrl(Uri.parse('http://localhost:8000/health'));
        final response = await request.close();
        if (response.statusCode == 200) {
          debugPrint('[Backend] API hazır! (${i + 1}. deneme)');
          client.close();
          return true;
        }
      } catch (_) {
        // Henüz hazır değil
      }
      await Future.delayed(const Duration(seconds: 1));
    }

    client.close();
    debugPrint('[Backend] API 10sn içinde hazır olmadı.');
    return false;
  }

  /// Backend'i temiz bir şekilde sonlandır
  Future<void> stopBackend() async {
    if (!_isRunning || _pid == null) return;

    try {
      debugPrint('[Backend] Sonlandırılıyor (PID: $_pid)...');

      // Önce nazikçe sonlandırmayı dene (SIGTERM)
      final killed = Process.killPid(_pid!, ProcessSignal.sigterm);

      if (killed) {
        debugPrint('[Backend] SIGTERM gönderildi.');
        // 3 saniye bekle
        await Future.delayed(const Duration(seconds: 3));

        // Hala çalışıyorsa zorla sonlandır
        try {
          Process.killPid(_pid!, ProcessSignal.sigkill);
          debugPrint('[Backend] SIGKILL gönderildi.');
        } catch (_) {
          // Zaten kapanmış olabilir
        }
      }
    } catch (e) {
      debugPrint('[Backend] Sonlandırma hatası: $e');
    } finally {
      _isRunning = false;
      _backendProcess = null;
      _pid = null;
      debugPrint('[Backend] Süreç temizlendi.');
    }
  }

  /// Singleton
  static final BackendProcessManager _instance = BackendProcessManager._internal();
  factory BackendProcessManager() => _instance;
  BackendProcessManager._internal();
}
