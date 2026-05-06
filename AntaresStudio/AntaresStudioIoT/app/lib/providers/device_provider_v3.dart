/// AntaresStudio IoT - Device Provider v3.0
///
/// Manages ESP32-CAM connection (local WiFi AP: 192.168.4.1)
/// AND sends telemetry to backend via WebSocket (real-time, no polling)
///
/// v3.0 Changes:
///   [WebSocket] Real-time telemetry to backend (replaces HTTP polling)
///   [Database] Historical telemetry storage via backend SQLite
///   [Lazy] Automatic backend sync when PC is connected

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../services/esp32_service.dart';
import '../services/websocket_service.dart';

// ============================================================
// Connection States
// ============================================================

enum DeviceConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

// ============================================================
// Device Provider v3.0 with WebSocket
// ============================================================

class DeviceProvider extends ChangeNotifier {
  final ESP32Service _esp32 = ESP32Service();
  final WebSocketService _ws = WebSocketService();

  // ESP32 Local Connection State
  DeviceConnectionState _connectionState = DeviceConnectionState.disconnected;
  ESP32Status? _espStatus;
  ArduinoSensorData _sensorData = ArduinoSensorData();
  String _firmwareVersion = '--';
  String _statusMessage = 'Disconnected';

  // Backend WebSocket State
  bool _backendConnected = false;
  StreamSubscription? _wsSubscription;

  // Retry config
  static const int _maxRetries = 3;
  static const int _retryBaseDelayMs = 1000;
  int _retryCount = 0;
  int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailures = 5;

  // Data history (sparklines)
  final List<double> _temperatureHistory = [];
  final List<double> _humidityHistory = [];
  static const int _maxHistoryLength = 30;

  // Timers
  Timer? _pollTimer;
  Timer? _reconnectTimer;
  Timer? _telemetrySyncTimer;

  // Getters
  DeviceConnectionState get connectionState => _connectionState;
  ESP32Status? get espStatus => _espStatus;
  ArduinoSensorData get sensorData => _sensorData;
  String get firmwareVersion => _firmwareVersion;
  String get statusMessage => _statusMessage;
  bool get isConnected => _connectionState == DeviceConnectionState.connected;
  bool get backendConnected => _backendConnected;
  List<double> get temperatureHistory => List.unmodifiable(_temperatureHistory);
  List<double> get humidityHistory => List.unmodifiable(_humidityHistory);

  static const String espHost = '192.168.4.1';
  ESP32Service get esp32 => _esp32;

  /// Initialize with backend URL for WebSocket
  void initialize({String backendUrl = 'http://localhost:8000'}) {
    _ws.initialize(backendUrl);
    
    // Listen to WebSocket connection state
    _wsSubscription = _ws.connectionStateStream.listen((state) {
      _backendConnected = state == WebSocketConnectionState.connected;
      if (_backendConnected) {
        debugPrint('[DeviceProvider] Backend WebSocket connected');
      }
      notifyListeners();
    });
    
    // Connect to backend WebSocket for telemetry
    _ws.connectTelemetry();
    _ws.connectLogs();
  }

  /// Connect to ESP32 capsule with retry
  Future<void> connect() async {
    if (_connectionState == DeviceConnectionState.connecting) return;

    _connectionState = DeviceConnectionState.connecting;
    _retryCount = 0;
    _statusMessage = 'Searching for capsule...';
    notifyListeners();

    while (_retryCount < _maxRetries) {
      try {
        _statusMessage = _retryCount > 0
            ? 'Retrying... (${_retryCount + 1}/$_maxRetries)'
            : 'Searching for capsule...';
        notifyListeners();

        final status = await _esp32.getStatus();
        if (status != null) {
          // Successful ESP32 connection
          _espStatus = status;
          _connectionState = DeviceConnectionState.connected;
          _firmwareVersion = status.version;
          _statusMessage = 'Connected to capsule';
          _retryCount = 0;
          _consecutiveFailures = 0;

          // Get Arduino sensor data
          _sensorData = status.arduino;
          _addToHistory(_sensorData);

          // Start local polling (for immediate UI updates)
          _startPolling();
          
          // Start telemetry sync to backend
          _startTelemetrySync();

          notifyListeners();
          return;
        }
      } catch (e) {
        debugPrint('[DeviceProvider] Connection error (attempt ${_retryCount + 1}): $e');
      }

      _retryCount++;

      if (_retryCount < _maxRetries) {
        final delay = _retryBaseDelayMs * (1 << _retryCount);
        _statusMessage = 'Waiting... ${delay ~/ 1000}s';
        notifyListeners();
        await Future.delayed(Duration(milliseconds: delay));
      }
    }

    // All attempts failed
    _connectionState = DeviceConnectionState.error;
    _statusMessage = 'Capsule not found!\nConnect to Wi-Fi: ANTARES_KAPSUL_LAB';
    notifyListeners();
  }

  /// Poll ESP32 for local data (every 2 seconds)
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final status = await _esp32.getStatus();
        if (status != null) {
          _espStatus = status;
          _sensorData = status.arduino;
          _addToHistory(_sensorData);

          _consecutiveFailures = 0;
          if (_connectionState != DeviceConnectionState.connected) {
            _connectionState = DeviceConnectionState.connected;
            _statusMessage = 'Connected to capsule';
          }
        } else {
          _consecutiveFailures++;
        }
      } catch (_) {
        _consecutiveFailures++;
      }

      // Too many failures → reconnect mode
      if (_consecutiveFailures >= _maxConsecutiveFailures) {
        _connectionState = DeviceConnectionState.reconnecting;
        _statusMessage = 'Connection lost. Reconnecting...';
        _pollTimer?.cancel();
        _startReconnect();
      }

      notifyListeners();
    });
  }

  /// Send telemetry to backend WebSocket (every 2 seconds)
  void _startTelemetrySync() {
    _telemetrySyncTimer?.cancel();
    _telemetrySyncTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_backendConnected) {
        await _sendTelemetryToBackend();
      }
    });
  }

  /// Send current sensor data to backend
  Future<void> _sendTelemetryToBackend() async {
    try {
      final data = {
        'temperature': _sensorData.temperature,
        'humidity': _sensorData.humidity,
        'soil_moisture': _sensorData.soilMoisture,
        'mode': _sensorData.mode.name,
        'heater_power': _sensorData.heaterPower,
        'fan_sly': _sensorData.fanSly,
        'fan_dz': _sensorData.fanDz,
        'motor_position': _sensorData.motorPosition,
        'is_homed': _sensorData.isHomed,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      await _ws.sendTelemetry(data);
    } catch (e) {
      debugPrint('[DeviceProvider] Telemetry send failed: $e');
    }
  }

  /// Auto-reconnect (every 5 seconds)
  void _startReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final status = await _esp32.getStatus();
        if (status != null) {
          _espStatus = status;
          _connectionState = DeviceConnectionState.connected;
          _firmwareVersion = status.version;
          _statusMessage = 'Reconnected to capsule';
          _consecutiveFailures = 0;
          _reconnectTimer?.cancel();
          _startPolling();
          _startTelemetrySync();
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  /// Capture photo from ESP32
  Future<Uint8List?> capturePhoto() async {
    if (!isConnected) return null;
    return await _esp32.capturePhoto();
  }

  /// Send command to Arduino (via ESP32)
  Future<ArduinoCommandResult?> sendArduinoCommand(String cmd) async {
    return await _esp32.sendArduinoCommand(cmd);
  }

  /// Motor home command
  Future<bool> motorHome() async {
    return await _esp32.motorHome();
  }

  /// Pause autonomous mode
  Future<bool> pauseAutonomous() async {
    return await _esp32.pauseAutonomous();
  }

  /// Resume autonomous mode
  Future<bool> resumeAutonomous() async {
    return await _esp32.resumeAutonomous();
  }

  /// Add to data history
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

  /// Manual telemetry sync (can be called by UI)
  Future<void> syncTelemetryNow() async {
    if (_backendConnected) {
      await _sendTelemetryToBackend();
    }
  }

  /// Disconnect from ESP32
  void disconnect() {
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    _telemetrySyncTimer?.cancel();
    _connectionState = DeviceConnectionState.disconnected;
    _consecutiveFailures = 0;
    _statusMessage = 'Disconnected';
    notifyListeners();
  }

  /// Full disconnect (ESP32 + Backend)
  void disconnectAll() {
    disconnect();
    _ws.disconnect();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    _telemetrySyncTimer?.cancel();
    _wsSubscription?.cancel();
    _esp32.dispose();
    _ws.dispose();
    super.dispose();
  }
}
