/// AntaresStudio IoT - Black Box (Kara Kutu) Provider v3.2
///
/// Manages mission recording state, controls ESP32 recording,
/// and handles report generation/download.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../services/esp32_service.dart';
import '../services/websocket_service.dart';

// ============================================================
// Recording States
// ============================================================

enum RecordingState {
  idle,
  starting,
  recording,
  stopping,
  uploading,
  generating,
  completed,
  error,
}

// ============================================================
// Black Box Provider
// ============================================================

class BlackBoxProvider extends ChangeNotifier {
  final ESP32Service _esp32 = ESP32Service();
  final WebSocketService _ws = WebSocketService();
  
  // Recording state
  RecordingState _state = RecordingState.idle;
  bool _isRecording = false;
  DateTime? _recordingStartTime;
  int _recordedSeconds = 0;
  Timer? _recordingTimer;
  
  // Report state
  String? _lastReportUrl;
  String? _lastReportFilename;
  Map<String, dynamic>? _lastReportStats;
  String? _errorMessage;
  
  // Status from ESP32
  bool _espRecordingStatus = false;
  StreamSubscription? _wsSubscription;
  
  // Getters
  RecordingState get state => _state;
  bool get isRecording => _isRecording || _espRecordingStatus;
  bool get isProcessing => _state == RecordingState.stopping || 
                           _state == RecordingState.uploading ||
                           _state == RecordingState.generating;
  DateTime? get recordingStartTime => _recordingStartTime;
  int get recordedSeconds => _recordedSeconds;
  String get recordedDuration => _formatDuration(_recordedSeconds);
  String? get lastReportUrl => _lastReportUrl;
  String? get lastReportFilename => _lastReportFilename;
  Map<String, dynamic>? get lastReportStats => _lastReportStats;
  String? get errorMessage => _errorMessage;
  bool get hasReport => _lastReportUrl != null;
  
  // ============================================================
  // Initialization
  // ============================================================
  
  void initialize() {
    // Listen to WebSocket for real-time recording status
    _wsSubscription = _ws.telemetryStream.listen((telemetry) {
      final wasRecording = _espRecordingStatus;
      _espRecordingStatus = telemetry['is_record'] ?? false;
      
      // Auto-sync if ESP32 started/stopped recording independently
      if (_espRecordingStatus != wasRecording) {
        if (_espRecordingStatus && _state != RecordingState.recording) {
          _state = RecordingState.recording;
          _recordingStartTime = DateTime.now();
          _startRecordingTimer();
        } else if (!_espRecordingStatus && _state == RecordingState.recording) {
          _state = RecordingState.idle;
          _stopRecordingTimer();
        }
        notifyListeners();
      }
    });
  }
  
  // ============================================================
  // Recording Control
  // ============================================================
  
  /// Start recording on ESP32
  Future<bool> startRecording() async {
    if (isRecording) {
      debugPrint('[BlackBox] Already recording');
      return false;
    }
    
    _setState(RecordingState.starting);
    _errorMessage = null;
    
    try {
      final result = await _esp32.sendBlackBoxCommand('START');
      
      if (result != null && result.success) {
        _isRecording = true;
        _recordingStartTime = DateTime.now();
        _recordedSeconds = 0;
        _setState(RecordingState.recording);
        _startRecordingTimer();
        
        debugPrint('[BlackBox] Recording started');
        return true;
      } else {
        _setError('Failed to start recording on capsule');
        return false;
      }
    } catch (e) {
      _setError('Start recording error: $e');
      return false;
    }
  }
  
  /// Stop recording on ESP32 and upload data
  Future<bool> stopRecording() async {
    if (!isRecording) {
      debugPrint('[BlackBox] Not recording');
      return false;
    }
    
    _setState(RecordingState.stopping);
    _stopRecordingTimer();
    
    try {
      // Send STOP command - this triggers ESP32 to upload
      final result = await _esp32.sendBlackBoxCommand('STOP');
      
      if (result != null && result.success) {
        // ESP32 is now uploading, wait for backend processing
        _setState(RecordingState.uploading);
        
        // Poll for report generation (max 30 seconds)
        final reportInfo = await _waitForReportGeneration(timeoutSeconds: 30);
        
        if (reportInfo != null) {
          _lastReportUrl = reportInfo['pdf_url'];
          _lastReportFilename = reportInfo['pdf_filename'];
          _lastReportStats = reportInfo['statistics'];
          _isRecording = false;
          _setState(RecordingState.completed);
          
          debugPrint('[BlackBox] Report generated: $_lastReportFilename');
          return true;
        } else {
          _setError('Report generation timed out');
          return false;
        }
      } else {
        _setError('Failed to stop recording');
        return false;
      }
    } catch (e) {
      _setError('Stop recording error: $e');
      return false;
    }
  }
  
  /// Wait for backend to generate PDF report
  Future<Map<String, dynamic>?> _waitForReportGeneration({
    required int timeoutSeconds
  }) async {
    final startTime = DateTime.now();
    
    while (DateTime.now().difference(startTime).inSeconds < timeoutSeconds) {
      try {
        // Check for latest report
        final response = await http.get(
          Uri.parse('${_esp32.baseUrl}/api/v1/blackbox/reports/list'),
        );
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final reports = data['reports'] as List<dynamic>;
          
          if (reports.isNotEmpty) {
            // Get the most recent report
            final latest = reports.first;
            final reportTime = DateTime.parse(latest['created']);
            
            // Check if this report was created after we stopped recording
            if (_recordingStartTime != null && 
                reportTime.isAfter(_recordingStartTime!)) {
              // Fetch full report details
              final detailResponse = await http.get(
                Uri.parse('${_esp32.baseUrl}${latest['url'].replaceFirst('/api/v1', '/api/v1')}'),
              );
              
              if (detailResponse.statusCode == 200) {
                return {
                  'pdf_url': latest['url'],
                  'pdf_filename': latest['filename'],
                  'statistics': null, // Would need separate endpoint for stats
                };
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[BlackBox] Polling error: $e');
      }
      
      await Future.delayed(const Duration(seconds: 2));
    }
    
    return null;
  }
  
  /// Download the generated report
  Future<String?> downloadReport({String? filename}) async {
    final targetFilename = filename ?? _lastReportFilename;
    if (targetFilename == null) return null;
    
    try {
      final url = filename != null 
          ? '${_esp32.baseUrl}/api/v1/blackbox/reports/$filename'
          : '${_esp32.baseUrl}/api/v1/blackbox/reports/latest';
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        // Save to downloads directory
        final dir = await getExternalStorageDirectory() ?? 
                    await getApplicationDocumentsDirectory();
        final downloadsDir = Directory('${dir.path}/AntaresReports');
        await downloadsDir.create(recursive: true);
        
        final localPath = '${downloadsDir.path}/$targetFilename';
        final file = File(localPath);
        await file.writeAsBytes(response.bodyBytes);
        
        debugPrint('[BlackBox] Report saved to: $localPath');
        return localPath;
      }
    } catch (e) {
      debugPrint('[BlackBox] Download error: $e');
    }
    
    return null;
  }
  
  /// Get list of all reports
  Future<List<Map<String, dynamic>>> getReportsList() async {
    try {
      final response = await http.get(
        Uri.parse('${_esp32.baseUrl}/api/v1/blackbox/reports/list'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['reports']);
      }
    } catch (e) {
      debugPrint('[BlackBox] List reports error: $e');
    }
    
    return [];
  }
  
  // ============================================================
  // Timer Management
  // ============================================================
  
  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _recordedSeconds++;
      notifyListeners();
    });
  }
  
  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }
  
  // ============================================================
  // Helpers
  // ============================================================
  
  void _setState(RecordingState state) {
    _state = state;
    notifyListeners();
  }
  
  void _setError(String message) {
    _state = RecordingState.error;
    _errorMessage = message;
    _isRecording = false;
    notifyListeners();
  }
  
  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m ${secs}s';
    } else if (minutes > 0) {
      return '${minutes}m ${secs}s';
    } else {
      return '${secs}s';
    }
  }
  
  /// Reset state for new recording session
  void reset() {
    _state = RecordingState.idle;
    _isRecording = false;
    _recordingStartTime = null;
    _recordedSeconds = 0;
    _errorMessage = null;
    _stopRecordingTimer();
    notifyListeners();
  }
  
  /// Clear last report
  void clearLastReport() {
    _lastReportUrl = null;
    _lastReportFilename = null;
    _lastReportStats = null;
    notifyListeners();
  }
  
  @override
  void dispose() {
    _recordingTimer?.cancel();
    _wsSubscription?.cancel();
    super.dispose();
  }
}
