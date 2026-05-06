/// AntaresStudio IoT - Scan Provider v3.0 with WebSocket
///
/// 360° scan orchestration with real-time pipeline monitoring
/// via WebSocket (replaces HTTP polling)
///
/// v3.0 Changes:
///   [WebSocket] Real-time pipeline progress (replaces 5s polling)
///   [WebSocket] Instant status updates from backend
///   [Database] Pipeline status persisted in SQLite

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../services/esp32_service.dart';
import '../services/backend_service.dart';
import '../services/websocket_service.dart';

// ============================================================
// Scan States
// ============================================================

enum ScanState {
  idle,
  connecting,
  homing,
  scanning,
  paused,
  uploading,
  cleaning,
  pipelineRunning,
  completed,
  error,
}

// ============================================================
// Scan Provider v3.0 with WebSocket
// ============================================================

class ScanProvider extends ChangeNotifier {
  final ESP32Service _esp32 = ESP32Service();
  final BackendService _backend = BackendService();
  final WebSocketService _ws = WebSocketService();

  // --- State ---
  ScanState _state = ScanState.idle;
  int _currentStep = 0;
  int _totalSteps = 0;
  double _currentAngle = 0;
  String _statusMessage = 'Ready';
  String? _errorMessage;
  String? _sessionId;

  // --- Configuration ---
  int numPhotos = 8;
  double stepAngle = 45.0;
  int stabilizationDelayMs = 800;

  // --- Captured photos ---
  final List<Uint8List> _capturedPhotos = [];

  // Pipeline state
  String? _pipelineId;
  PipelineStatus? _pipelineStatus;
  StreamSubscription? _pipelineSubscription;

  // Connection loss handling
  int _scanResumeStep = 0;
  bool _isCancelling = false;

  // Getters
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
  // 360° Scan Orchestration
  // ============================================================

  /// Start 360° scan
  Future<void> startScan({int? photos, double? angle}) async {
    if (isActive) return;

    numPhotos = photos ?? numPhotos;
    stepAngle = angle ?? (360.0 / numPhotos);
    _totalSteps = numPhotos;
    _currentStep = 0;
    _capturedPhotos.clear();
    _errorMessage = null;
    _isCancelling = false;

    _setState(ScanState.connecting, 'Connecting to capsule...');

    try {
      // Test connection
      final status = await _esp32.getStatus();
      if (status == null) {
        _setError('Cannot connect to capsule!');
        return;
      }

      _setState(ScanState.homing, 'Motor homing...');
      final homeResult = await _esp32.motorHome();
      if (!homeResult) {
        _setError('Motor home failed!');
        return;
      }

      _currentAngle = 0;
      _setState(ScanState.scanning, 'Starting 360° scan...');

      // Capture loop
      for (int i = 0; i < numPhotos; i++) {
        if (_isCancelling) {
          _setState(ScanState.idle, 'Scan cancelled');
          return;
        }

        // Check connection
        final ping = await _esp32.getStatus();
        if (ping == null) {
          _scanResumeStep = i;
          _setState(ScanState.paused, 'Connection lost! Scan paused.');
          _startAutoResume();
          return;
        }

        _currentStep = i + 1;
        _currentAngle = i * stepAngle;
        _statusMessage = 'Capturing photo ${_currentStep}/${numPhotos} (${_currentAngle.toStringAsFixed(0)}°)';
        notifyListeners();

        // Capture photo
        final photo = await _esp32.capturePhoto();
        if (photo != null) {
          _capturedPhotos.add(photo);
        }

        // Rotate motor (except after last photo)
        if (i < numPhotos - 1) {
          final moveResult = await _esp32.sendArduinoCommand('STEP');
          if (moveResult == null || !moveResult.success) {
            _scanResumeStep = i + 1;
            _setState(ScanState.paused, 'Motor error! Scan paused.');
            _startAutoResume();
            return;
          }

          // Wait for stabilization
          await Future.delayed(Duration(milliseconds: stabilizationDelayMs));
        }
      }

      _currentAngle = 0;
      _setState(ScanState.completed,
          'Scan complete! ${_capturedPhotos.length} photos captured.');

    } catch (e) {
      _setError('Scan error: $e');
    }
  }

  /// Pause scan
  void pauseScan() {
    if (_state == ScanState.scanning) {
      _scanResumeStep = _currentStep;
      _setState(ScanState.paused, 'Scan paused manually.');
    }
  }

  /// Resume scan
  Future<void> resumeScan() async {
    if (_state != ScanState.paused) return;

    _setState(ScanState.scanning, 'Resuming scan...');

    try {
      // Test connection
      final status = await _esp32.getStatus();
      if (status == null) {
        _setState(ScanState.paused, 'Still disconnected. Waiting...');
        _startAutoResume();
        return;
      }

      // Continue from where we left off
      for (int i = _scanResumeStep; i < numPhotos; i++) {
        if (_isCancelling) {
          _setState(ScanState.idle, 'Scan cancelled');
          return;
        }

        _currentStep = i + 1;
        _currentAngle = i * stepAngle;
        _statusMessage = 'Capturing photo ${_currentStep}/${numPhotos} (${_currentAngle.toStringAsFixed(0)}°)';
        notifyListeners();

        // Capture
        final photo = await _esp32.capturePhoto();
        if (photo != null) {
          _capturedPhotos.add(photo);
        }

        // Rotate (except after last)
        if (i < numPhotos - 1) {
          final moveResult = await _esp32.sendArduinoCommand('STEP');
          if (moveResult == null || !moveResult.success) {
            _scanResumeStep = i + 1;
            _setState(ScanState.paused, 'Motor error! Scan paused.');
            _startAutoResume();
            return;
          }

          await Future.delayed(Duration(milliseconds: stabilizationDelayMs));
        }
      }

      _currentAngle = 0;
      _setState(ScanState.completed,
          'Scan complete! ${_capturedPhotos.length} photos captured.');

    } catch (e) {
      _setError('Resume error: $e');
      _startAutoResume();
    }
  }

  /// Cancel scan
  void cancelScan() {
    _isCancelling = true;
    _setState(ScanState.idle, 'Scan cancelled');
  }

  /// Auto-resume timer
  void _startAutoResume() {
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_state != ScanState.paused || _isCancelling) {
        timer.cancel();
        return;
      }

      try {
        final status = await _esp32.getStatus();
        if (status != null) {
          timer.cancel();
          await resumeScan();
        }
      } catch (_) {}
    });
  }

  // ============================================================
  // Photo Upload
  // ============================================================

  /// Upload photos to backend
  Future<String?> uploadToBackend(List<Uint8List> photos) async {
    if (photos.isEmpty) {
      _setError('No photos to upload!');
      return null;
    }

    _setState(ScanState.uploading, 'Uploading photos to backend...');

    try {
      String? sid;
      for (int i = 0; i < photos.length; i++) {
        _currentStep = i + 1;
        _totalSteps = photos.length;
        _statusMessage = 'Uploading: ${i + 1}/${photos.length}...';
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

        await Future.delayed(Duration.zero); // Yield to event loop
      }

      _setState(ScanState.completed,
          '${photos.length} photos uploaded. Session: $sid');
      return sid;
    } catch (e) {
      _setError('Upload error: $e');
      return null;
    }
  }

  /// Start background cleaning (rembg)
  Future<bool> startBackgroundCleaning() async {
    if (_sessionId == null) return false;

    _setState(ScanState.cleaning, 'Starting background removal...');
    final success = await _backend.cleanBackgrounds(_sessionId!);

    if (success) {
      _setState(ScanState.completed, 'Background removal started.');
    } else {
      _setError('Background removal failed!');
    }
    return success;
  }

  // ============================================================
  // Pipeline Monitoring (WebSocket v3.0)
  // ============================================================

  /// Start Meshroom pipeline and monitor via WebSocket
  Future<void> startPipelineAndMonitor({bool useCleaned = true}) async {
    if (_sessionId == null) {
      _setError('No Session ID! Upload photos first.');
      return;
    }

    _setState(ScanState.pipelineRunning, 'Starting pipeline...');

    try {
      final result = await _backend.startPipeline(
        _sessionId!,
        useCleaned: useCleaned,
      );

      if (result == null) {
        _setError('Pipeline failed to start!');
        return;
      }

      _pipelineId = result.pipelineId;
      _pipelineStatus = result;

      // Subscribe to WebSocket for real-time updates
      _subscribeToPipelineWebSocket();

    } catch (e) {
      _setError('Pipeline error: $e');
    }
  }

  /// Subscribe to pipeline WebSocket (replaces polling)
  void _subscribeToPipelineWebSocket() {
    if (_pipelineId == null) return;

    // Cancel any existing subscription
    _pipelineSubscription?.cancel();

    // Subscribe via WebSocket
    _ws.subscribeToPipeline(_pipelineId!);

    // Listen to pipeline updates
    _pipelineSubscription = _ws.pipelineStream.listen((update) {
      // Only process updates for our pipeline
      if (update.pipelineId != _pipelineId) return;

      _pipelineStatus = PipelineStatus(
        pipelineId: update.pipelineId,
        status: update.status,
        progress: update.progress,
        currentStep: update.currentStep,
        isCompleted: update.status == 'completed',
        isFailed: update.status == 'failed',
        outputPath: null,
      );

      _statusMessage = 'Pipeline: ${update.currentStep} (${update.progress.toStringAsFixed(0)}%)';

      // Check completion
      if (update.status == 'completed') {
        _setState(ScanState.completed, 'Pipeline complete! Model ready.');
        _ws.unsubscribeFromPipeline(_pipelineId!);
      } else if (update.status == 'failed') {
        _setError('Pipeline failed during ${update.currentStep}');
        _ws.unsubscribeFromPipeline(_pipelineId!);
      }

      notifyListeners();
    });
  }

  /// Legacy fallback: Manual status check (if WebSocket fails)
  Future<void> checkPipelineStatusManual() async {
    if (_pipelineId == null) return;

    try {
      final status = await _backend.getPipelineStatus(_pipelineId!);
      if (status != null) {
        _pipelineStatus = status;
        _statusMessage = 'Pipeline: ${status.currentStep} (${status.progress}%)';

        if (status.isCompleted) {
          _setState(ScanState.completed, 'Pipeline complete! Model ready.');
        } else if (status.isFailed) {
          _setError('Pipeline failed!');
        }

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Manual pipeline check failed: $e');
    }
  }

  /// Cancel pipeline
  Future<void> cancelPipeline() async {
    if (_pipelineId == null) return;

    await _backend.cancelPipeline(_pipelineId!);
    _ws.unsubscribeFromPipeline(_pipelineId!);
    _pipelineSubscription?.cancel();

    _setState(ScanState.idle, 'Pipeline cancelled');
  }

  /// Download 3D model
  Future<Uint8List?> downloadModel() async {
    if (_pipelineId == null) return null;
    return await _backend.downloadModel(_pipelineId!);
  }

  // ============================================================
  // Cleanup
  // ============================================================

  /// Trigger auto-cleanup
  Future<bool> triggerAutoCleanup() async {
    try {
      return await _backend.cleanupAllCache();
    } catch (e) {
      debugPrint('Auto-cleanup failed: $e');
      return false;
    }
  }

  /// Reset state
  void reset() {
    _state = ScanState.idle;
    _currentStep = 0;
    _totalSteps = 0;
    _currentAngle = 0;
    _statusMessage = 'Ready';
    _errorMessage = null;
    _sessionId = null;
    _capturedPhotos.clear();
    _pipelineId = null;
    _pipelineStatus = null;
    _pipelineSubscription?.cancel();
    _pipelineSubscription = null;
    if (_pipelineId != null) {
      _ws.unsubscribeFromPipeline(_pipelineId!);
    }
    notifyListeners();
  }

  // Helper methods
  void _setState(ScanState state, String message) {
    _state = state;
    _statusMessage = message;
    notifyListeners();
  }

  void _setError(String message) {
    _state = ScanState.error;
    _errorMessage = message;
    _statusMessage = 'Error: $message';
    notifyListeners();
  }

  @override
  void dispose() {
    _pipelineSubscription?.cancel();
    if (_pipelineId != null) {
      _ws.unsubscribeFromPipeline(_pipelineId!);
    }
    super.dispose();
  }
}

// Pipeline status model (matches backend)
class PipelineStatus {
  final String pipelineId;
  final String status;
  final double progress;
  final String currentStep;
  final bool isCompleted;
  final bool isFailed;
  final String? outputPath;

  PipelineStatus({
    required this.pipelineId,
    required this.status,
    required this.progress,
    required this.currentStep,
    required this.isCompleted,
    required this.isFailed,
    this.outputPath,
  });
}
