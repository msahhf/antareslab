/// AntaresStudio IoT - Güncelleme Dialog'u
///
/// Yeni sürüm mevcut olduğunda gösterilen şık, modern dialog.
/// Release notlarını gösterir, indirme bağlantısı sunar.

import 'package:flutter/material.dart';
import '../services/app_update_service.dart';
import '../theme/app_theme.dart';

/// Güncelleme dialog'unu göster
///
/// [context]: BuildContext
/// [versionInfo]: Uzak sürüm bilgisi
///
/// Kullanım:
/// ```dart
/// await showUpdateDialog(context, versionInfo);
/// ```
Future<void> showUpdateDialog(
  BuildContext context,
  AppVersionInfo versionInfo,
) async {
  return showDialog(
    context: context,
    barrierDismissible: !versionInfo.isForceUpdate,
    barrierColor: Colors.black87,
    builder: (context) => _UpdateDialog(versionInfo: versionInfo),
  );
}

class _UpdateDialog extends StatefulWidget {
  final AppVersionInfo versionInfo;

  const _UpdateDialog({required this.versionInfo});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  bool _isDownloading = false;
  double _downloadProgress = 0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleUpdate() async {
    final url = widget.versionInfo.downloadUrl;
    if (url == null || url.isEmpty) return;

    // Doğrudan tarayıcıda aç
    await AppUpdateService.openDownloadUrl(url);

    if (!widget.versionInfo.isForceUpdate && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.versionInfo;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AntaresColors.surface,
                  AntaresColors.surfaceElevated,
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AntaresColors.primary.withOpacity(0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: AntaresColors.primary.withOpacity(0.08),
                  blurRadius: 40,
                  spreadRadius: 0,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ---- Header ----
                _buildHeader(info),

                // ---- Sürüm bilgisi ----
                _buildVersionBadges(info),

                // ---- Release Notları ----
                if (info.releaseNotes != null && info.releaseNotes!.isNotEmpty)
                  _buildReleaseNotes(info.releaseNotes!),

                // ---- İndirme ilerleme ----
                if (_isDownloading) _buildDownloadProgress(),

                // ---- Butonlar ----
                _buildActions(info),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Gradient header (ikon + başlık)
  Widget _buildHeader(AppVersionInfo info) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AntaresColors.primary.withOpacity(0.12),
            AntaresColors.primary.withOpacity(0.03),
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Animasyonlu ikon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: AntaresColors.primaryGradient,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AntaresColors.primary.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: const Icon(
              Icons.system_update_alt_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),

          // Başlık
          Text(
            info.isForceUpdate
                ? 'Zorunlu Güncelleme'
                : 'Güncelleme Mevcut',
            style: const TextStyle(
              color: AntaresColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),

          Text(
            info.releaseName ?? 'Yeni sürüm hazır!',
            style: const TextStyle(
              color: AntaresColors.textSecondary,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Sürüm karşılaştırma badge'leri
  Widget _buildVersionBadges(AppVersionInfo info) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Mevcut sürüm
          _versionBadge(
            label: 'Mevcut',
            version: 'v$kAppVersion',
            color: AntaresColors.textDisabled,
          ),

          // Ok ikonu
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Icon(
              Icons.arrow_forward_rounded,
              color: AntaresColors.primary.withOpacity(0.5),
              size: 20,
            ),
          ),

          // Yeni sürüm
          _versionBadge(
            label: 'Yeni',
            version: 'v${info.latestVersion}',
            color: AntaresColors.primary,
            highlight: true,
          ),
        ],
      ),
    );
  }

  Widget _versionBadge({
    required String label,
    required String version,
    required Color color,
    bool highlight = false,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: color.withOpacity(0.6),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: highlight
                ? AntaresColors.primary.withOpacity(0.12)
                : AntaresColors.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: highlight
                  ? AntaresColors.primary.withOpacity(0.3)
                  : AntaresColors.border,
            ),
          ),
          child: Text(
            version,
            style: TextStyle(
              color: highlight ? AntaresColors.primary : AntaresColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  /// Release notları alanı (kaydırılabilir)
  Widget _buildReleaseNotes(String notes) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.text_snippet_outlined,
                  size: 14, color: AntaresColors.textDisabled),
              SizedBox(width: 6),
              Text(
                'Yenilikler',
                style: TextStyle(
                  color: AntaresColors.textDisabled,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 150),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AntaresColors.background.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AntaresColors.border.withOpacity(0.5)),
            ),
            child: SingleChildScrollView(
              child: Text(
                notes.trim(),
                style: const TextStyle(
                  color: AntaresColors.textSecondary,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// İndirme ilerleme çubuğu
  Widget _buildDownloadProgress() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _downloadProgress > 0 ? _downloadProgress : null,
              backgroundColor: AntaresColors.surfaceElevated,
              color: AntaresColors.primary,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _downloadProgress > 0
                ? 'İndiriliyor: ${(_downloadProgress * 100).toStringAsFixed(0)}%'
                : 'İndirme başlatılıyor...',
            style: const TextStyle(
              color: AntaresColors.textDisabled,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  /// Alt butonlar
  Widget _buildActions(AppVersionInfo info) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Row(
        children: [
          // "Sonra" butonu (zorunlu güncellemede görünmez)
          if (!info.isForceUpdate)
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Sonra',
                  style: TextStyle(
                    color: AntaresColors.textDisabled,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

          if (!info.isForceUpdate) const SizedBox(width: 12),

          // "Güncelle" butonu
          Expanded(
            flex: info.isForceUpdate ? 1 : 1,
            child: ElevatedButton.icon(
              onPressed: _isDownloading ? null : _handleUpdate,
              icon: _isDownloading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(
                _isDownloading ? 'İndiriliyor...' : 'Güncelle',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AntaresColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
