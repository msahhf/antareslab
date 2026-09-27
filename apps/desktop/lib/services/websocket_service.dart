// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// WebSocket connection states
enum WebSocketConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// Real-time telemetry data model
class TelemetryData {
  final double? temperature;
  final int? humidity;
  final int? soilMoisture;
  final String mode;
  final int heaterPower;
  final bool fanSly;
  final bool fanDz;
  final int motorPosition;
  final bool isHomed;
  final DateTime? timestamp;

  TelemetryData({
    this.temperature,
    this.humidity,
    this.soilMoisture,
    this.mode = 'STANDBY',
    this.heaterPower = 0,
    this.fanSly = false,
    this.fanDz = false,
    this.motorPosition = 0,
    this.isHomed = false,
    this.timestamp,
  });

  factory TelemetryData.fromJson(Map<String, dynamic> json) {
    return TelemetryData(
      temperature: json['temperature']?.toDouble(),
      humidity: json['humidity'],
      soilMoisture: json['soil_moisture'],
      mode: json['mode'] ?? 'STANDBY',
      heaterPower: json['heater_power'] ?? 0,
      fanSly: json['fan_sly'] ?? false,
      fanDz: json['fan_dz'] ?? false,
      motorPosition: json['motor_position'] ?? 0,
      isHomed: json['is_homed'] ?? false,
      timestamp: json['timestamp'] != null 
          ? DateTime.tryParse(json['timestamp']) 
          : null,
    );
  }
}

/// Pipeline update from WebSocket
class PipelineUpdate {
  final String pipelineId;
  final String status;
  final double progress;
  final String currentStep;
  final DateTime timestamp;

  PipelineUpdate({
    required this.pipelineId,
    required this.status,
    required this.progress,
    required this.currentStep,
    required this.timestamp,
  });

  factory PipelineUpdate.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? {};
    return PipelineUpdate(
      pipelineId: json['pipeline_id'] ?? '',
      status: data['status'] ?? 'unknown',
      progress: (data['progress'] ?? 0).toDouble(),
      currentStep: data['current_step'] ?? '',
      timestamp: DateTime.tryParse(json['timestamp']) ?? DateTime.now(),
    );
  }
}

/// System log entry from WebSocket
class SystemLogEntry {
  final DateTime timestamp;
  final String level;
  final String source;
  final String message;

  SystemLogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
  });

  factory SystemLogEntry.fromJson(Map<String, dynamic> json) {
    return SystemLogEntry(
      timestamp: DateTime.tryParse(json['timestamp']) ?? DateTime.now(),
      level: json['level'] ?? 'INFO',
      source: json['source'] ?? 'system',
      message: json['message'] ?? '',
    );
  }
}

/// Antares WebSocket Service
/// 
/// Manages real-time connections for:
/// - Telemetry updates (replaces polling)
/// - Pipeline progress (replaces polling)
/// - System logs (for dashboard)
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  // WebSocket connections
  WebSocket? _telemetrySocket;
  WebSocket? _logsSocket;
  final Map<String, WebSocket> _pipelineSockets = {};

  // Connection state
  final _connectionStateController = StreamController<WebSocketConnectionState>.broadcast();
  Stream<WebSocketConnectionState> get connectionStateStream => _connectionStateController.stream;

  // Data streams
  final _telemetryController = StreamController<TelemetryData>.broadcast();
  Stream<TelemetryData> get telemetryStream => _telemetryController.stream;

  final _pipelineController = StreamController<PipelineUpdate>.broadcast();
  Stream<PipelineUpdate> get pipelineStream => _pipelineController.stream;

  final _logsController = StreamController<SystemLogEntry>.broadcast();
  Stream<SystemLogEntry> get logsStream => _logsController.stream;

  // Connection config
  String _baseUrl = 'ws://localhost:8000';
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _shouldReconnect = false;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  static const Duration reconnectDelay = Duration(seconds: 3);

  WebSocketConnectionState _state = WebSocketConnectionState.disconnected;
  WebSocketConnectionState get state => _state;

  /// Initialize with backend URL
  void initialize(String backendUrl) {
    // Convert http:// to ws://
    _baseUrl = backendUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
    debugPrint('WebSocketService initialized: $_baseUrl');
  }

  /// Connect to telemetry stream (replaces HTTP polling)
  Future<void> connectTelemetry() async {
    if (_telemetrySocket != null) return;

    _updateState(WebSocketConnectionState.connecting);

    try {
      final url = '$_baseUrl/ws/telemetry';
      debugPrint('Connecting to telemetry WebSocket: $url');

      _telemetrySocket = await WebSocket.connect(url);
      _shouldReconnect = true;
      _reconnectAttempts = 0;
      _updateState(WebSocketConnectionState.connected);

      // Listen for messages
      _telemetrySocket!.listen(
        _handleTelemetryMessage,
        onError: (error) {
          debugPrint('Telemetry WebSocket error: $error');
          _updateState(WebSocketConnectionState.error);
        },
        onDone: () {
          debugPrint('Telemetry WebSocket closed');
          _telemetrySocket = null;
          if (_shouldReconnect) {
            _scheduleReconnect();
          } else {
            _updateState(WebSocketConnectionState.disconnected);
          }
        },
        cancelOnError: true,
      );

      // Start ping to keep connection alive
      _startPingTimer();

    } catch (e) {
      debugPrint('Failed to connect telemetry WebSocket: $e');
      _updateState(WebSocketConnectionState.error);
      _scheduleReconnect();
    }
  }

  /// Connect to system logs stream (for dashboard)
  Future<void> connectLogs() async {
    if (_logsSocket != null) return;

    try {
      final url = '$_baseUrl/ws/logs';
      _logsSocket = await WebSocket.connect(url);

      _logsSocket!.listen(
        _handleLogsMessage,
        onError: (error) => debugPrint('Logs WebSocket error: $error'),
        onDone: () => _logsSocket = null,
        cancelOnError: false,
      );

      // Request recent history
      _logsSocket!.add(jsonEncode({'action': 'get_history', 'limit': 50}));

    } catch (e) {
      debugPrint('Failed to connect logs WebSocket: $e');
    }
  }

  /// Subscribe to specific pipeline updates (replaces polling)
  Future<void> subscribeToPipeline(String pipelineId) async {
    if (_pipelineSockets.containsKey(pipelineId)) return;

    try {
      final url = '$_baseUrl/ws/pipeline/$pipelineId';
      final socket = await WebSocket.connect(url);

      _pipelineSockets[pipelineId] = socket;

      socket.listen(
        _handlePipelineMessage,
        onError: (error) => debugPrint('Pipeline $pipelineId error: $error'),
        onDone: () {
          _pipelineSockets.remove(pipelineId);
        },
        cancelOnError: false,
      );

    } catch (e) {
      debugPrint('Failed to subscribe to pipeline $pipelineId: $e');
    }
  }

  /// Unsubscribe from pipeline updates
  void unsubscribeFromPipeline(String pipelineId) {
    final socket = _pipelineSockets.remove(pipelineId);
    socket?.close();
  }

  /// Disconnect all WebSockets
  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();

    _telemetrySocket?.close();
    _telemetrySocket = null;

    _logsSocket?.close();
    _logsSocket = null;

    for (final socket in _pipelineSockets.values) {
      socket.close();
    }
    _pipelineSockets.clear();

    _updateState(WebSocketConnectionState.disconnected);
  }

  // Message handlers
  void _handleTelemetryMessage(dynamic message) {
    try {
      final data = jsonDecode(message);

      if (data['type'] == 'telemetry') {
        final telemetry = TelemetryData.fromJson(data['data']);
        _telemetryController.add(telemetry);
      } else if (data['type'] == 'pong') {
        // Ping response received, connection is alive
      }
    } catch (e) {
      debugPrint('Error parsing telemetry: $e');
    }
  }

  void _handlePipelineMessage(dynamic message) {
    try {
      final data = jsonDecode(message);

      if (data['type'] == 'pipeline_update') {
        final update = PipelineUpdate.fromJson(data);
        _pipelineController.add(update);
      }
    } catch (e) {
      debugPrint('Error parsing pipeline update: $e');
    }
  }

  void _handleLogsMessage(dynamic message) {
    try {
      final data = jsonDecode(message);

      if (data['type'] == 'log') {
        final log = SystemLogEntry.fromJson(data);
        _logsController.add(log);
      } else if (data['type'] == 'log_history') {
        // Batch of historical logs
        final logs = data['logs'] as List;
        for (final logJson in logs) {
          final log = SystemLogEntry.fromJson(logJson);
          _logsController.add(log);
        }
      }
    } catch (e) {
      debugPrint('Error parsing log: $e');
    }
  }

  // Connection management
  void _updateState(WebSocketConnectionState newState) {
    _state = newState;
    _connectionStateController.add(newState);
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_telemetrySocket != null) {
        try {
          _telemetrySocket!.add(jsonEncode({'action': 'ping'}));
        } catch (e) {
          debugPrint('Ping failed: $e');
        }
      }
    });
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= maxReconnectAttempts) {
      debugPrint('Max reconnect attempts reached');
      _updateState(WebSocketConnectionState.disconnected);
      return;
    }

    _reconnectAttempts++;
    _updateState(WebSocketConnectionState.reconnecting);

    debugPrint('Scheduling reconnect attempt $_reconnectAttempts/$maxReconnectAttempts');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectDelay, () {
      connectTelemetry();
    });
  }

  /// Send telemetry data to backend (via HTTP POST, as backup to WebSocket)
  Future<void> sendTelemetry(Map<String, dynamic> data) async {
    try {
      // Use HTTP POST for sending data (WebSocket is for receiving)
      // This could also be done via WebSocket if backend supports bidirectional
      final http = await HttpClient().postUrl(Uri.parse('$_baseUrl/api/telemetry'));
      http.headers.contentType = ContentType.json;
      http.write(jsonEncode(data));
      await http.close();
    } catch (e) {
      debugPrint('Failed to send telemetry: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _telemetryController.close();
    _pipelineController.close();
    _logsController.close();
    _connectionStateController.close();
  }
}
