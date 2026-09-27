// SPDX-License-Identifier: Apache-2.0

/// AntaresStudio IoT - Tarama Orkestrasyon Provider'ı v2.1
///
/// 360° tarama iş akışını ve SD kart aktarımını yönetir.
/// Tüm karar mekanizmaları burada, Arduino sadece komut uygulayıcı.
///
/// v2.1 Değişiklikler:
///   [2] Bağlantı kopması algılama (her adımda ping + timeout)
///   [2] Güvenli duraklatma: tarama sırasında Wi-Fi kesilirse
///   [5] Asenkron pipeline izleme (Meshroom/rembg ilerlemesi)
///   [5] Pipeline status polling (UI kilitlenmez)

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../services/esp32_service.dart';
import '../services/backend_service.dart';

// ============================================================
// Tarama Durumları
// ============================================================

enum ScanState {
  idle,              // Hazır
  connecting,        // Arduino'ya bağlanılıyor
  homing,            // Motor Home
  scanning,          // Fotoğraf + döndürme döngüsü
  paused,            // [2] Bağlantı kesildi, tarama duraklatıldı
  uploading,         // Backend'e yükleme
  cleaning,          // rembg arka plan temizleme
  pipelineRunning,   // [5] Meshroom pipeline çalışıyor
  completed,         // Tamamlandı
  error,             // Hata
}

// ============================================================
// Scan Provider
// ============================================================

class ScanProvider extends ChangeNotifier {
  final ESP32Service _esp32 = ESP32Service();
  final BackendService _backend = BackendService();

  // --- Durum ---
  ScanState _state = ScanState.idle;
  int _currentStep = 0;
  int _totalSteps = 0;
  double _currentAngle = 0;
  String _statusMessage = 'Hazır';
  String? _errorMessage;
  String? _sessionId;

  // --- Yapılandırma ---
  int numPhotos = 8;
  double stepAngle = 45.0;
  int stabilizationDelayMs = 800;  // [1] Artırıldı

  // --- Çekilen fotoğraflar ---
  final List<Uint8List> _capturedPhotos = [];

  // [5] Pipeline durumu
  String? _pipelineId;
  PipelineStatus? _pipelineStatus;
  Timer? _pipelinePollTimer;

  // [2] Bağlantı kopması için
  int _scanResumeStep = 0;
  bool _isCancelling = false;

  // Getter'lar
  ScanState get state => _state;
  int get currentStep => _currentStep;
  int get totalSteps => _totalSteps;
  double get currentAngle => _currentAngle;
  String get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  String? get sessionId => _sessionId;
  List<Uint8List> get capturedPhotos => List.unmodifiable(_capturedPhotos);
  PipelineStatus? get pipelineStatus => _pipelineStatus;
  bool get isActive => _state != ScanState.idle &&
      _state != ScanState.completed &&
      _state != ScanState.error &&
      _state != ScanState.paused;
  bool get isPaused => _state == ScanState.paused;
  bool get isPipelineRunning => _state == ScanState.pipelineRunning;
  int get progressPercent =>
      _totalSteps > 0 ? ((_currentStep / _totalSteps) * 100).round() : 0;

  // ============================================================
  // 360° Tarama Orkestrasyon
  // ============================================================

  /// 360° tarama başlat
  Future<void> startScan({int? photos, double? angle}) async {
    if (isActive) return;

    numPhotos = photos ?? numPhotos;
    stepAngle = angle ?? (360.0 / numPhotos);
    _totalSteps = numPhotos;
    _currentStep = 0;
    _capturedPhotos.clear();
    _errorMessage = null;
    _isCancelling = false;

    try {
      // 1. Bağlantı kontrolü
      _setState(ScanState.connecting, 'ESP32 bağlantısı kontrol ediliyor...');
      if (!await _verifyConnection()) return;

      // 2. Otonom modu duraklat
      _setState(ScanState.connecting, 'Otonom mod duraklatılıyor...');
      await _esp32.pauseAutonomous();
      await Future.delayed(const Duration(milliseconds: 500));

      // 3. Motor Home
      _setState(ScanState.homing, 'Motor Home pozisyonuna dönülüyor...');
      final homeResult = await _esp32.motorHome();
      if (!homeResult) {
        _setError('Motor Home komutu başarısız!');
        await _safeResumeAutonomous();
        return;
      }
      await Future.delayed(const Duration(seconds: 1));

      // 4. Motor etkinleştir
      await _esp32.motorEnable(true);

      // 5. Tarama döngüsü
      _setState(ScanState.scanning, 'Tarama başlıyor...');
      await _executeScanLoop(startFrom: 0);

    } catch (e) {
      // [2] Bağlantı kopması tespiti
      if (e is TimeoutException || e.toString().contains('Connection')) {
        _pauseScan('Bağlantı kesildi! Tarama duraklatıldı.');
      } else {
        _setError('Tarama hatası: $e');
        await _safeResumeAutonomous();
      }
    }
  }

  /// [2] Tarama döngüsünü çalıştır (başlangıç adımından)
  Future<void> _executeScanLoop({required int startFrom}) async {
    for (int i = startFrom; i < numPhotos; i++) {
      if (_isCancelling) break;

      _currentStep = i + 1;
      _currentAngle = i * stepAngle;

      // [2] Her adımda bağlantı kontrolü
      if (i > startFrom && i % 2 == 0) {
        final isAlive = await _esp32.ping();
        if (!isAlive) {
          _pauseScan(
              'Bağlantı kesildi! $i/$numPhotos tamamlandı. Devam etmek için "Resume" basın.');
          _scanResumeStep = i;
          return;
        }
      }

      // 5a. Fotoğraf çek
      _statusMessage = 'Fotoğraf ${i + 1}/$numPhotos çekiliyor...';
      notifyListeners();

      Uint8List? jpeg;
      // [2] 3 deneme (geçici ağ hatası koruması)
      for (int attempt = 0; attempt < 3; attempt++) {
        jpeg = await _esp32.capturePhoto();
        if (jpeg != null) break;
        await Future.delayed(const Duration(seconds: 1));
      }

      if (jpeg == null) {
        _pauseScan('Fotoğraf ${i + 1} çekilemedi (3 deneme). Tarama duraklatıldı.');
        _scanResumeStep = i;
        return;
      }
      _capturedPhotos.add(jpeg);

      // 5b. Motor döndür (son fotoğrafta dönmeye gerek yok)
      if (i < numPhotos - 1) {
        _statusMessage =
            'Motor döndürülüyor (${((i + 1) * stepAngle).toStringAsFixed(0)}°)...';
        notifyListeners();

        final rotateOk = await _esp32.motorRotate((i + 1) * stepAngle);
        if (!rotateOk) {
          _pauseScan('Motor komutu başarısız! Tarama duraklatıldı.');
          _scanResumeStep = i + 1;
          return;
        }
        await Future.delayed(Duration(milliseconds: stabilizationDelayMs));
      }
    }

    if (!_isCancelling) {
      // 6. Otonom moda devam
      await _safeResumeAutonomous();

      // 7. Tamamlandı
      _setState(ScanState.completed,
          'Tarama tamamlandı! ${_capturedPhotos.length} fotoğraf çekildi.');
    }
  }

  /// [2] Duraklatılmış taramaya devam et
  Future<void> resumeScan() async {
    if (_state != ScanState.paused) return;

    _setState(ScanState.scanning, 'Taramaya devam ediliyor...');

    if (!await _verifyConnection()) return;

    try {
      await _executeScanLoop(startFrom: _scanResumeStep);
    } catch (e) {
      if (e is TimeoutException || e.toString().contains('Connection')) {
        _pauseScan('Bağlantı tekrar kesildi!');
      } else {
        _setError('Tarama hatası: $e');
        await _safeResumeAutonomous();
      }
    }
  }

  /// Taramayı iptal et
  Future<void> cancelScan() async {
    if (!isActive && !isPaused) return;
    _isCancelling = true;
    try {
      await _esp32.sendArduinoCommand('X');
      await _safeResumeAutonomous();
    } catch (_) {}
    _setState(ScanState.idle, 'Tarama iptal edildi.');
  }

  // ============================================================
  // SD Kart Aktarım (V3.0: Devre dışı - Direct Transfer Kullanılıyor)
  // ============================================================

  // ============================================================
  // Backend'e Yükleme
  // ============================================================

  /// Çekilen/aktarılan fotoğrafları backend'e yükle - NON-BLOCKING
  Future<String?> uploadToBackend(List<Uint8List> photos) async {
    if (photos.isEmpty) return null;

    try {
      _setState(ScanState.uploading, 'Fotoğraflar backend\'e yükleniyor...');

      String? sid;
      for (int i = 0; i < photos.length; i++) {
        _currentStep = i + 1;
        _totalSteps = photos.length;
        _statusMessage = 'Yükleniyor: ${i + 1}/${photos.length}...';
        notifyListeners();

        final result = await _backend.uploadPhoto(
          photos[i],
          sessionId: sid,
          filename: 'photo_${i.toString().padLeft(4, '0')}.jpg',
        );

        if (result != null) {
          sid = result.sessionId;
          _sessionId = sid;
        }
        
        // CRITICAL: Yield control to Flutter event loop between uploads
        // This prevents UI freezing during long upload operations
        await Future.delayed(Duration.zero);
      }

      _setState(ScanState.completed,
          'Backend\'e ${photos.length} fotoğraf yüklendi. Session: $sid');
      return sid;
    } catch (e) {
      _setError('Backend yükleme hatası: $e');
      return null;
    }
  }

  /// rembg arka plan temizleme başlat
  Future<bool> startBackgroundCleaning() async {
    if (_sessionId == null) return false;

    _setState(ScanState.cleaning, 'Arka plan temizleme başlatılıyor...');
    final success = await _backend.cleanBackgrounds(_sessionId!);

    if (success) {
      _setState(ScanState.completed, 'Arka plan temizleme başlatıldı.');
    } else {
      _setError('Arka plan temizleme başlatılamadı!');
    }
    return success;
  }

  // ============================================================
  // [5] Pipeline İzleme (Asenkron)
  // ============================================================

  /// Meshroom pipeline başlat ve asenkron izle
  Future<void> startPipelineAndMonitor({bool useCleaned = true}) async {
    if (_sessionId == null) {
      _setError('Session ID yok! Önce fotoğraf yükleyin.');
      return;
    }

    _setState(ScanState.pipelineRunning, 'Pipeline başlatılıyor...');

    try {
      final result = await _backend.startPipeline(
        _sessionId!,
        useCleaned: useCleaned,
      );

      if (result == null) {
        _setError('Pipeline başlatılamadı!');
        return;
      }

      _pipelineId = result.pipelineId;
      _pipelineStatus = result;

      // Periyodik polling başlat
      _startPipelinePolling();
    } catch (e) {
      _setError('Pipeline hatası: $e');
    }
  }

  /// [5] Pipeline durumunu periyodik sorgula
  void _startPipelinePolling() {
    _pipelinePollTimer?.cancel();
    _pipelinePollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_pipelineId == null) {
        _pipelinePollTimer?.cancel();
        return;
      }

      try {
        final status = await _backend.getPipelineStatus(_pipelineId!);
        if (status != null) {
          _pipelineStatus = status;
          _statusMessage =
              'Pipeline: ${status.currentStep} (${status.progress}%)';

          if (status.isCompleted) {
            _pipelinePollTimer?.cancel();
            _setState(ScanState.completed,
                'Pipeline tamamlandı! Model: ${status.outputModel ?? 'Hazır'}');
          } else if (status.isError) {
            _pipelinePollTimer?.cancel();
            _setError('Pipeline hatası: ${status.error ?? 'Bilinmiyor'}');
          }

          notifyListeners();
        }
      } catch (e) {
        // Ağ hatası — polling devam eder
        debugPrint('[ScanProvider] Pipeline poll hatası: $e');
      }
    });
  }

  /// Pipeline iptal et
  Future<void> cancelPipeline() async {
    if (_pipelineId == null) return;
    _pipelinePollTimer?.cancel();
    await _backend.cancelPipeline(_pipelineId!);
    _setState(ScanState.idle, 'Pipeline iptal edildi.');
  }

  // ============================================================
  // Yardımcılar
  // ============================================================

  /// [2] Bağlantı doğrulama
  Future<bool> _verifyConnection() async {
    final connected = await _esp32.ping();
    if (!connected) {
      _setError(
          'ESP32 bağlantısı kurulamadı!\nWi-Fi: ANTARES_KAPSUL_LAB ağına bağlı olduğunuzdan emin olun.');
      return false;
    }
    return true;
  }

  /// [2] Güvenli otonom devam (bağlantı kopmuş olabilir)
  Future<void> _safeResumeAutonomous() async {
    try {
      await _esp32.resumeAutonomous();
    } catch (_) {
      debugPrint('[ScanProvider] Otonom devam komutu gönderilemedi.');
    }
  }

  /// [2] Taramayı duraklatma
  void _pauseScan(String message) {
    _state = ScanState.paused;
    _statusMessage = message;
    _errorMessage = null;
    notifyListeners();
  }

  void _setState(ScanState newState, String message) {
    _state = newState;
    _statusMessage = message;
    notifyListeners();
  }

  void _setError(String message) {
    _state = ScanState.error;
    _errorMessage = message;
    _statusMessage = message;
    notifyListeners();
  }

  /// Durumu sıfırla
  void reset() {
    _pipelinePollTimer?.cancel();
    _state = ScanState.idle;
    _currentStep = 0;
    _totalSteps = 0;
    _currentAngle = 0;
    _statusMessage = 'Hazır';
    _errorMessage = null;
    _pipelineId = null;
    _pipelineStatus = null;
    _isCancelling = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _pipelinePollTimer?.cancel();
    _esp32.dispose();
    _backend.dispose();
    super.dispose();
  }
}
