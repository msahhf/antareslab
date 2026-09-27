// SPDX-License-Identifier: Apache-2.0

/// AntaresStudio IoT - Cihaz Bağlantı Provider'ı v2.1
///
/// ESP32-CAM (AP: 192.168.4.1) ile bağlantıyı yöneten,
/// Arduino sensör verilerini tutan ve periyodik sorgulayan ChangeNotifier.
///
/// v2.1 Değişiklikler:
///   [4] Retry mekanizması (max 3 deneme, exponent backoff)
///   [4] Otomatik yeniden bağlanma (polling sırasında bağlantı koparsa)
///   [4] Ardışık hata sayacı ile net hata durumu (sonsuz connecting önleme)

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../services/esp32_service.dart';

// ============================================================
// Bağlantı Durumları
// ============================================================

enum DeviceConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,   // [4] Otomatik yeniden bağlanma
  error,
}

// ============================================================
// Device Provider
// ============================================================

class DeviceProvider extends ChangeNotifier {
  final ESP32Service _esp32 = ESP32Service();

  // Durum
  DeviceConnectionState _connectionState = DeviceConnectionState.disconnected;
  ESP32Status? _espStatus;
  ArduinoSensorData _sensorData = ArduinoSensorData();
  String _firmwareVersion = '--';
  String _statusMessage = 'Bağlı değil';

  // [4] Retry konfigürasyon
  static const int _maxRetries = 3;
  static const int _retryBaseDelayMs = 1000;
  int _retryCount = 0;
  int _consecutiveFailures = 0;     // Polling sırasındaki ardışık hatalar
  static const int _maxConsecutiveFailures = 5;

  // Veri geçmişi (sparkline için)
  final List<double> _temperatureHistory = [];
  final List<double> _humidityHistory = [];
  static const int _maxHistoryLength = 30;

  // Zamanlayıcı
  Timer? _pollTimer;
  Timer? _reconnectTimer;

  // Getter'lar
  DeviceConnectionState get connectionState => _connectionState;
  ESP32Status? get espStatus => _espStatus;
  ArduinoSensorData get sensorData => _sensorData;
  String get firmwareVersion => _firmwareVersion;
  String get statusMessage => _statusMessage;
  bool get isConnected => _connectionState == DeviceConnectionState.connected;
  List<double> get temperatureHistory => List.unmodifiable(_temperatureHistory);
  List<double> get humidityHistory => List.unmodifiable(_humidityHistory);

  static const String espHost = '192.168.4.1';
  ESP32Service get esp32 => _esp32;

  /// [4] Cihaza bağlan — Retry mekanizmalı
  Future<void> connect() async {
    if (_connectionState == DeviceConnectionState.connecting) return;

    _connectionState = DeviceConnectionState.connecting;
    _retryCount = 0;
    _statusMessage = 'Kapsül aranıyor...';
    notifyListeners();

    while (_retryCount < _maxRetries) {
      try {
        _statusMessage = _retryCount > 0
            ? 'Tekrar deneniyor... (${_retryCount + 1}/$_maxRetries)'
            : 'Kapsül aranıyor...';
        notifyListeners();

        final status = await _esp32.getStatus();
        if (status != null) {
          // Başarılı bağlantı
          _espStatus = status;
          _connectionState = DeviceConnectionState.connected;
          _firmwareVersion = status.version;
          _statusMessage = 'Kapsüle bağlandı';
          _retryCount = 0;
          _consecutiveFailures = 0;

          // Arduino sensör verilerini al
          _sensorData = status.arduino;
          _addToHistory(_sensorData);

          _startPolling();
          notifyListeners();
          return;
        }
      } catch (e) {
        debugPrint('[DeviceProvider] Bağlantı hatası (deneme ${_retryCount + 1}): $e');
      }

      _retryCount++;

      if (_retryCount < _maxRetries) {
        // Exponential backoff
        final delay = _retryBaseDelayMs * (1 << _retryCount);
        _statusMessage = 'Bekleniyor... ${delay ~/ 1000}sn';
        notifyListeners();
        await Future.delayed(Duration(milliseconds: delay));
      }
    }

    // Tüm denemeler başarısız
    _connectionState = DeviceConnectionState.error;
    _statusMessage = 'Kapsül bulunamadı!\nWi-Fi: ANTARES_KAPSUL_LAB ağına bağlanın.';
    notifyListeners();
  }

  /// [4] Periyodik veri sorgulama — otomatik yeniden bağlanma
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        // ESP32 durumu
        final status = await _esp32.getStatus();
        if (status != null) {
          _espStatus = status;

          // Arduino sensör verileri
          _sensorData = status.arduino;
          _addToHistory(_sensorData);

          // Bağlantı geri geldi
          _consecutiveFailures = 0;
          if (_connectionState != DeviceConnectionState.connected) {
            _connectionState = DeviceConnectionState.connected;
            _statusMessage = 'Kapsüle bağlandı';
          }
        } else {
          _consecutiveFailures++;
        }
      } catch (_) {
        _consecutiveFailures++;
      }

      // [4] Ardışık hata eşiği aşıldı → yeniden bağlanma moduna geç
      if (_consecutiveFailures >= _maxConsecutiveFailures) {
        _connectionState = DeviceConnectionState.reconnecting;
        _statusMessage = 'Bağlantı kesildi. Yeniden bağlanılıyor...';
        _pollTimer?.cancel();
        _startReconnect();
      }

      notifyListeners();
    });
  }

  /// [4] Otomatik yeniden bağlanma (5 saniyede bir dene)
  void _startReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final status = await _esp32.getStatus();
        if (status != null) {
          _espStatus = status;
          _connectionState = DeviceConnectionState.connected;
          _firmwareVersion = status.version;
          _statusMessage = 'Kapsüle yeniden bağlandı';
          _consecutiveFailures = 0;
          _reconnectTimer?.cancel();
          _startPolling();
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  /// Fotoğraf çek
  Future<Uint8List?> capturePhoto() async {
    if (!isConnected) return null;
    return await _esp32.capturePhoto();
  }

  /// Arduino'ya komut gönder
  Future<ArduinoCommandResult?> sendArduinoCommand(String cmd) async {
    return await _esp32.sendArduinoCommand(cmd);
  }

  /// Motor Home
  Future<bool> motorHome() async {
    return await _esp32.motorHome();
  }

  /// Otonom modu duraklat
  Future<bool> pauseAutonomous() async {
    return await _esp32.pauseAutonomous();
  }

  /// Otonom moda devam
  Future<bool> resumeAutonomous() async {
    return await _esp32.resumeAutonomous();
  }

  /// Veri geçmişine ekle
  void _addToHistory(ArduinoSensorData data) {
    _temperatureHistory.add(data.temperature);
    _humidityHistory.add(data.humidity.toDouble());

    if (_temperatureHistory.length > _maxHistoryLength) {
      _temperatureHistory.removeAt(0);
    }
    if (_humidityHistory.length > _maxHistoryLength) {
      _humidityHistory.removeAt(0);
    }
  }

  /// Bağlantıyı kes
  void disconnect() {
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    _connectionState = DeviceConnectionState.disconnected;
    _consecutiveFailures = 0;
    _statusMessage = 'Bağlı değil';
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    _esp32.dispose();
    super.dispose();
  }
}
