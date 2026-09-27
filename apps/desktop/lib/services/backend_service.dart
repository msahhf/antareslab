/// AntaresStudio IoT - Python Backend HTTP İstemcisi v2.1
///
/// Lokal backend (localhost:8000) ile iletişim.
/// Fotoğraf yükleme, rembg arka plan temizleme, Meshroom pipeline.
///
/// v2.1 Değişiklikler:
///   [3] Session cleanup + disk usage sorgu
///   [4] Optimize model indirme (GLB/GLTF)
///   [5] Genişletilmiş pipeline status (optimized_model, cache_cleaned, duration)

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Oturum durumu
class PhotoSession {
  final String sessionId;
  final int photoCount;
  final String? cleaningStatus;
  final int cleanedCount;

  PhotoSession({
    required this.sessionId,
    this.photoCount = 0,
    this.cleaningStatus,
    this.cleanedCount = 0,
  });

  factory PhotoSession.fromJson(Map<String, dynamic> json) {
    return PhotoSession(
      sessionId: json['session_id'] ?? '',
      photoCount: json['photo_count'] ?? json['total_photos'] ?? 0,
      cleaningStatus: json['cleaning_status'],
      cleanedCount: json['cleaned_count'] ?? 0,
    );
  }
}

/// Pipeline durumu — [5] genişletilmiş
class PipelineStatus {
  final String pipelineId;
  final String status;
  final int progress;
  final String currentStep;
  final String? error;
  final String? outputModel;
  final String? optimizedModel;    // [4] GLB/GLTF model yolu
  final double? durationSec;       // [5] Pipeline süresi
  final bool cacheCleaned;         // [3] Cache temizlendi mi

  PipelineStatus({
    required this.pipelineId,
    required this.status,
    this.progress = 0,
    this.currentStep = '',
    this.error,
    this.outputModel,
    this.optimizedModel,
    this.durationSec,
    this.cacheCleaned = false,
  });

  factory PipelineStatus.fromJson(Map<String, dynamic> json) {
    return PipelineStatus(
      pipelineId: json['pipeline_id'] ?? '',
      status: json['status'] ?? 'unknown',
      progress: json['progress'] ?? 0,
      currentStep: json['current_step'] ?? '',
      error: json['error'],
      outputModel: json['output_model'],
      optimizedModel: json['optimized_model'],
      durationSec: (json['duration_sec'] as num?)?.toDouble(),
      cacheCleaned: json['cache_cleaned'] ?? false,
    );
  }

  bool get isRunning => status == 'running' || status == 'queued';
  bool get isCompleted => status == 'completed';
  bool get isError => status == 'error';
  bool get hasOptimizedModel => optimizedModel != null && optimizedModel!.isNotEmpty;

  String get durationFormatted {
    if (durationSec == null) return '--';
    final mins = (durationSec! / 60).floor();
    final secs = (durationSec! % 60).floor();
    return '${mins}dk ${secs}sn';
  }
}

/// [3] Disk kullanım bilgisi
class DiskUsage {
  final double uploadsMb;
  final double cleanedMb;
  final double outputMb;
  final double cacheMb;
  final double modelsMb;
  final double totalMb;

  DiskUsage({
    this.uploadsMb = 0,
    this.cleanedMb = 0,
    this.outputMb = 0,
    this.cacheMb = 0,
    this.modelsMb = 0,
    this.totalMb = 0,
  });

  factory DiskUsage.fromJson(Map<String, dynamic> json) {
    return DiskUsage(
      uploadsMb: (json['uploads_mb'] as num?)?.toDouble() ?? 0,
      cleanedMb: (json['cleaned_mb'] as num?)?.toDouble() ?? 0,
      outputMb: (json['output_mb'] as num?)?.toDouble() ?? 0,
      cacheMb: (json['cache_mb'] as num?)?.toDouble() ?? 0,
      modelsMb: (json['models_mb'] as num?)?.toDouble() ?? 0,
      totalMb: (json['total_mb'] as num?)?.toDouble() ?? 0,
    );
  }

  String get totalFormatted => totalMb > 1024
      ? '${(totalMb / 1024).toStringAsFixed(1)} GB'
      : '${totalMb.toStringAsFixed(0)} MB';
}

/// Python Backend HTTP İstemcisi
class BackendService {
  static const String _baseUrl = 'http://localhost:8000';
  static const Duration _timeout = Duration(seconds: 10);

  final http.Client _client;

  BackendService({http.Client? client}) : _client = client ?? http.Client();

  /// Backend sağlık kontrolü
  Future<bool> isHealthy() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ---- Fotoğraf Yükleme ----

  /// Tek fotoğraf yükle
  Future<PhotoSession?> uploadPhoto(
    Uint8List jpeg, {
    String? sessionId,
    String filename = 'capture.jpg',
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/v1/photos/upload'),
      );

      if (sessionId != null) {
        request.fields['session_id'] = sessionId;
      }

      request.files.add(http.MultipartFile.fromBytes(
        'file',
        jpeg,
        filename: filename,
      ));

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        return PhotoSession.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      print('[Backend] Upload hatası: $e');
    }
    return null;
  }

  /// Arkaplan temizleme başlat (rembg)
  Future<bool> cleanBackgrounds(String sessionId) async {
    try {
      final response = await _client
          .post(Uri.parse('$_baseUrl/api/v1/photos/clean/$sessionId'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['success'] == true;
      }
    } catch (e) {
      print('[Backend] Clean hatası: $e');
    }
    return false;
  }

  /// Oturum durumu
  Future<PhotoSession?> getSessionStatus(String sessionId) async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/v1/photos/status/$sessionId'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return PhotoSession.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  // ---- Pipeline (Meshroom) ----

  /// Fotogrametri pipeline başlat
  Future<PipelineStatus?> startPipeline(
    String sessionId, {
    bool useCleaned = true,
  }) async {
    try {
      final response = await _client
          .post(Uri.parse(
              '$_baseUrl/api/v1/pipeline/start/$sessionId?use_cleaned=$useCleaned'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return PipelineStatus.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      print('[Backend] Pipeline başlatma hatası: $e');
    }
    return null;
  }

  /// Pipeline durumu sorgula
  Future<PipelineStatus?> getPipelineStatus(String pipelineId) async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/v1/pipeline/status/$pipelineId'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return PipelineStatus.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  /// Pipeline iptal et
  Future<bool> cancelPipeline(String pipelineId) async {
    try {
      final response = await _client
          .delete(Uri.parse('$_baseUrl/api/v1/pipeline/cancel/$pipelineId'))
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (_) {}
    return false;
  }

  // ---- [4] Model İndirme ----

  /// Optimize edilmiş 3D modeli indir (GLB/GLTF)
  Future<Uint8List?> downloadModel(
    String pipelineId, {
    bool optimized = true,
  }) async {
    try {
      final response = await _client
          .get(Uri.parse(
              '$_baseUrl/api/v1/pipeline/model/$pipelineId?optimized=$optimized'))
          .timeout(const Duration(minutes: 5));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (e) {
      print('[Backend] Model indirme hatası: $e');
    }
    return null;
  }

  // ---- [3] Cleanup ----

  /// Session temizle (upload + cleaned + output + cache)
  Future<bool> cleanupSession(String sessionId) async {
    try {
      final response = await _client
          .post(Uri.parse('$_baseUrl/api/v1/pipeline/cleanup/$sessionId'))
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (_) {}
    return false;
  }

  /// Tüm cache'leri temizle
  Future<bool> cleanupAllCaches() async {
    try {
      final response = await _client
          .post(Uri.parse('$_baseUrl/api/v1/pipeline/cleanup/cache/all'))
          .timeout(const Duration(seconds: 30));
      return response.statusCode == 200;
    } catch (_) {}
    return false;
  }

  /// Disk kullanım bilgisi
  Future<DiskUsage?> getDiskUsage() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/v1/pipeline/disk-usage'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return DiskUsage.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    _client.close();
  }
}
