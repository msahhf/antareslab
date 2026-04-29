/// AntaresStudio IoT - Uygulama Güncelleme Servisi
///
/// GitHub Releases API veya uzak version_info.json dosyasından
/// uygulamanın güncel sürümünü kontrol eder.
///
/// Akış:
///   1. Uygulama açıldığında arka planda sürüm kontrolü
///   2. Yeni sürüm varsa şık "Güncelleme Mevcut" Dialog
///   3. Kullanıcı onaylarsa setup.exe indirme linki
///
/// Sürüm bilgisi kaynağı (öncelik sırası):
///   1. GitHub Releases API → /repos/{owner}/{repo}/releases/latest
///   2. Uzak JSON → https://raw.githubusercontent.com/.../version_info.json

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Mevcut uygulama sürümü — her release'de güncellenmeli
const String kAppVersion = '2.1.0';
const String kAppBuildNumber = '1';

/// Uzak sürüm bilgisi
class AppVersionInfo {
  final String latestVersion;
  final String? downloadUrl;
  final String? releaseNotes;
  final String? releaseName;
  final DateTime? publishedAt;
  final bool forceUpdate;        // Zorunlu güncelleme mi?
  final String? minVersion;      // Minimum desteklenen sürüm

  AppVersionInfo({
    required this.latestVersion,
    this.downloadUrl,
    this.releaseNotes,
    this.releaseName,
    this.publishedAt,
    this.forceUpdate = false,
    this.minVersion,
  });

  /// Güncelleme mevcut mu?
  bool get hasUpdate => _compareVersions(latestVersion, kAppVersion) > 0;

  /// Zorunlu güncelleme mi? (minVersion altındaysa)
  bool get isForceUpdate {
    if (forceUpdate) return true;
    if (minVersion != null) {
      return _compareVersions(minVersion!, kAppVersion) > 0;
    }
    return false;
  }

  /// Sürüm karşılaştırma: 1 (a > b), 0 (a == b), -1 (a < b)
  static int _compareVersions(String a, String b) {
    final aParts = a.replaceAll('v', '').split('.').map(int.tryParse).toList();
    final bParts = b.replaceAll('v', '').split('.').map(int.tryParse).toList();

    for (int i = 0; i < 3; i++) {
      final av = i < aParts.length ? (aParts[i] ?? 0) : 0;
      final bv = i < bParts.length ? (bParts[i] ?? 0) : 0;
      if (av > bv) return 1;
      if (av < bv) return -1;
    }
    return 0;
  }

  /// GitHub Release JSON'ından oluştur
  factory AppVersionInfo.fromGitHub(Map<String, dynamic> json) {
    // Setup.exe asset'ini bul
    String? setupUrl;
    final assets = (json['assets'] as List<dynamic>?) ?? [];
    for (final asset in assets) {
      final name = (asset['name'] as String).toLowerCase();
      if (name.contains('setup') && name.endsWith('.exe')) {
        setupUrl = asset['browser_download_url'] as String?;
        break;
      }
    }

    // Fallback: Setup yoksa release sayfasına yönlendir
    setupUrl ??= json['html_url'] as String?;

    return AppVersionInfo(
      latestVersion: (json['tag_name'] as String?)?.replaceAll('v', '') ?? '0.0.0',
      downloadUrl: setupUrl,
      releaseNotes: json['body'] as String?,
      releaseName: json['name'] as String?,
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'])
          : null,
    );
  }

  /// Uzak version_info.json'dan oluştur
  factory AppVersionInfo.fromVersionJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      latestVersion: json['version'] ?? '0.0.0',
      downloadUrl: json['download_url'],
      releaseNotes: json['release_notes'],
      releaseName: json['release_name'],
      forceUpdate: json['force_update'] ?? false,
      minVersion: json['min_version'],
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'])
          : null,
    );
  }
}

/// Uygulama güncelleme kontrol servisi
class AppUpdateService {
  /// GitHub repo (owner/repo)
  static const String _githubRepo = 'ScRien/antareslab';

  /// Alternatif: Uzak JSON URL (GitHub Raw veya kendi sunucunuz)
  static const String _versionJsonUrl =
      'https://raw.githubusercontent.com/$_githubRepo/main/version_info.json';

  final http.Client _client;

  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();

  /// Güncelleme kontrolü — önce GitHub, başarısızsa JSON fallback
  Future<AppVersionInfo?> checkForUpdate() async {
    // 1. GitHub Releases API dene
    final githubResult = await _checkGitHub();
    if (githubResult != null) return githubResult;

    // 2. Fallback: Uzak JSON dene
    final jsonResult = await _checkVersionJson();
    return jsonResult;
  }

  /// GitHub Releases API kontrolü
  Future<AppVersionInfo?> _checkGitHub() async {
    try {
      final url = 'https://api.github.com/repos/$_githubRepo/releases/latest';
      final response = await _client
          .get(
            Uri.parse(url),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return AppVersionInfo.fromGitHub(json);
      }
    } catch (e) {
      debugPrint('[AppUpdate] GitHub API hatası: $e');
    }
    return null;
  }

  /// Uzak version_info.json kontrolü
  Future<AppVersionInfo?> _checkVersionJson() async {
    try {
      final response = await _client
          .get(Uri.parse(_versionJsonUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return AppVersionInfo.fromVersionJson(json);
      }
    } catch (e) {
      debugPrint('[AppUpdate] Version JSON hatası: $e');
    }
    return null;
  }

  /// İndirme URL'ini tarayıcıda aç
  static Future<bool> openDownloadUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (e) {
      debugPrint('[AppUpdate] URL açma hatası: $e');
    }
    return false;
  }

  /// Setup.exe'yi uygulamanın yanına indir (isteğe bağlı)
  Future<String?> downloadSetup(
    String downloadUrl, {
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final streamedResponse = await _client.send(request);

      if (streamedResponse.statusCode != 200) return null;

      final totalBytes = streamedResponse.contentLength ?? 0;
      final bytes = <int>[];
      int received = 0;

      await for (final chunk in streamedResponse.stream) {
        bytes.addAll(chunk);
        received += chunk.length;
        onProgress?.call(received, totalBytes);
      }

      // Temp dizinine kaydet
      final tempDir = Directory.systemTemp;
      final setupFile = File('${tempDir.path}\\AntaresStudio_Setup.exe');
      await setupFile.writeAsBytes(bytes);

      return setupFile.path;
    } catch (e) {
      debugPrint('[AppUpdate] İndirme hatası: $e');
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}
