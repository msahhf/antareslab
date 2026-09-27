// SPDX-License-Identifier: Apache-2.0

/// AntaresStudio IoT - OTA Güncelleme Ekranı
///
/// GitHub Releases API üzerinden firmware sürümlerini kontrol eden,
/// indirme ve OTA güncelleme sürecini yöneten ekran.
///
/// Desteklenen güncelleme hedefleri:
///   - ESP32-CAM firmware (.bin)
///   - Arduino Nano firmware (.hex) → UART Bridge üzerinden
///   - Desktop App (.exe/.dmg) → bilgi amaçlı

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';
import '../services/update_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Güncelleme durumu
  UpdateManager? _updateManager;
  FirmwareRelease? _latestRelease;
  UpdateProgress _progress = UpdateProgress(status: UpdateStatus.idle);
  bool _isChecking = false;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _fadeController.forward();

    // UpdateManager'ı başlat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final device = context.read<DeviceProvider>();
      _updateManager = UpdateManager(
        githubRepo: 'msahhf/antareslab',
        espHost: DeviceProvider.espHost,
        currentEspVersion: device.firmwareVersion,
        onProgress: _onProgressUpdate,
      );
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _updateManager?.dispose();
    super.dispose();
  }

  void _onProgressUpdate(UpdateProgress progress) {
    if (mounted) {
      setState(() => _progress = progress);
    }
  }

  Future<void> _checkForUpdates() async {
    if (_isChecking || _updateManager == null) return;

    setState(() {
      _isChecking = true;
      _progress = UpdateProgress(
        status: UpdateStatus.checking,
        message: 'GitHub kontrol ediliyor...',
      );
    });

    final release = await _updateManager!.checkForUpdates();

    setState(() {
      _latestRelease = release;
      _isChecking = false;
    });
  }

  Future<void> _updateESP32() async {
    if (_isUpdating || _latestRelease?.espFirmware == null) return;

    setState(() => _isUpdating = true);
    await _updateManager!.updateESP32(_latestRelease!.espFirmware!);
    setState(() => _isUpdating = false);
  }

  Future<void> _updateArduino() async {
    if (_isUpdating || _latestRelease?.arduinoFirmware == null) return;

    setState(() => _isUpdating = true);
    await _updateManager!.updateArduino(_latestRelease!.arduinoFirmware!);
    setState(() => _isUpdating = false);
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Consumer<DeviceProvider>(
        builder: (context, device, _) {
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 8)),

              // Başlık kartı
              SliverToBoxAdapter(child: _buildHeaderCard(device)),

              // Güncelleme kontrol butonu
              SliverToBoxAdapter(child: _buildCheckButton()),

              // İlerleme göstergesi
              if (_progress.status != UpdateStatus.idle)
                SliverToBoxAdapter(child: _buildProgressCard()),

              // Release bilgileri
              if (_latestRelease != null) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Row(
                      children: [
                        Container(width: 3, height: 16,
                          decoration: BoxDecoration(
                            color: AntaresColors.success,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'MEVCUT SÜRÜM',
                          style: TextStyle(
                            color: AntaresColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.0,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Container(height: 1, color: AntaresColors.border)),
                      ],
                    ),
                  ),
                ),

                // Release kart
                SliverToBoxAdapter(child: _buildReleaseCard()),

                // Firmware kartları
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Row(
                      children: [
                        Container(width: 3, height: 16,
                          decoration: BoxDecoration(
                            color: AntaresColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'FİRMWARE DOSYALARI',
                          style: TextStyle(
                            color: AntaresColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.0,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Container(height: 1, color: AntaresColors.border)),
                      ],
                    ),
                  ),
                ),

                // ESP32 firmware kartı
                if (_latestRelease!.espFirmware != null)
                  SliverToBoxAdapter(
                    child: _buildFirmwareCard(
                      asset: _latestRelease!.espFirmware!,
                      deviceName: 'ESP32-CAM',
                      deviceIcon: Icons.wifi_rounded,
                      color: AntaresColors.primary,
                      description: 'Wi-Fi üzerinden OTA güncelleme',
                      onUpdate: device.isConnected ? _updateESP32 : null,
                    ),
                  ),

                // Arduino firmware kartı
                if (_latestRelease!.arduinoFirmware != null)
                  SliverToBoxAdapter(
                    child: _buildFirmwareCard(
                      asset: _latestRelease!.arduinoFirmware!,
                      deviceName: 'Arduino Nano',
                      deviceIcon: Icons.developer_board_rounded,
                      color: AntaresColors.secondary,
                      description: 'UART Bridge üzerinden güncelleme',
                      onUpdate: device.isConnected ? _updateArduino : null,
                    ),
                  ),
              ],

              // Boş durum
              if (_latestRelease == null && !_isChecking)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
    );
  }

  // ----------------------------------------------------------------
  // Header Kartı
  // ----------------------------------------------------------------
  Widget _buildHeaderCard(DeviceProvider device) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // İkon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AntaresColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.system_update_rounded,
                  color: AntaresColors.background, size: 24),
            ),
            const SizedBox(width: 14),

            // Bilgi
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'OTA Güncelleme Merkezi',
                    style: TextStyle(
                      color: AntaresColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    device.isConnected
                        ? 'Kapsül: v${device.firmwareVersion}'
                        : 'Kapsül bağlı değil',
                    style: TextStyle(
                      color: device.isConnected
                          ? AntaresColors.textSecondary
                          : AntaresColors.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // GitHub
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AntaresColors.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.code_rounded,
                      size: 14, color: AntaresColors.textSecondary),
                  SizedBox(width: 6),
                  Text(
                    'GitHub',
                    style: TextStyle(
                      color: AntaresColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // Kontrol Butonu
  // ----------------------------------------------------------------
  Widget _buildCheckButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: _isChecking || _isUpdating ? null : _checkForUpdates,
          icon: _isChecking
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AntaresColors.background,
                  ),
                )
              : const Icon(Icons.refresh_rounded, size: 20),
          label: Text(
            _isChecking ? 'Kontrol ediliyor...' : 'Güncellemeleri Kontrol Et',
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // İlerleme Kartı
  // ----------------------------------------------------------------
  Widget _buildProgressCard() {
    final isError = _progress.status == UpdateStatus.error;
    final isComplete = _progress.status == UpdateStatus.completed;
    final color = isError
        ? AntaresColors.error
        : isComplete
            ? AntaresColors.success
            : AntaresColors.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isError
                      ? Icons.error_outline_rounded
                      : isComplete
                          ? Icons.check_circle_outline_rounded
                          : Icons.downloading_rounded,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _progress.error ?? _progress.message,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),

            // İlerleme çubuğu
            if (_progress.progress > 0 && !isError && !isComplete) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress.progress,
                  minHeight: 6,
                  backgroundColor: AntaresColors.surfaceLight,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_progress.percentage}%',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // Release Kartı
  // ----------------------------------------------------------------
  Widget _buildReleaseCard() {
    final release = _latestRelease!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          gradient: AntaresColors.cardGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AntaresColors.border),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sürüm etiketi
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: AntaresColors.primaryGradient,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    release.tagName,
                    style: const TextStyle(
                      color: AntaresColors.background,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    release.name,
                    style: const TextStyle(
                      color: AntaresColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Yayınlanma tarihi
            Row(
              children: [
                const Icon(Icons.schedule_rounded,
                    size: 14, color: AntaresColors.textDisabled),
                const SizedBox(width: 6),
                Text(
                  _formatDate(release.publishedAt),
                  style: const TextStyle(
                    color: AntaresColors.textDisabled,
                    fontSize: 12,
                  ),
                ),
              ],
            ),

            // Release notları
            if (release.body.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AntaresColors.background.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  release.body,
                  style: const TextStyle(
                    color: AntaresColors.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // Firmware Kartı
  // ----------------------------------------------------------------
  Widget _buildFirmwareCard({
    required FirmwareAsset asset,
    required String deviceName,
    required IconData deviceIcon,
    required Color color,
    required String description,
    VoidCallback? onUpdate,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          gradient: AntaresColors.cardGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Cihaz ikonu
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(deviceIcon, color: color, size: 24),
            ),
            const SizedBox(width: 14),

            // Bilgiler
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deviceName,
                    style: const TextStyle(
                      color: AntaresColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      color: AntaresColors.textDisabled,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      // Dosya adı
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AntaresColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          asset.name,
                          style: const TextStyle(
                            color: AntaresColors.textSecondary,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${asset.sizeMB} MB',
                        style: const TextStyle(
                          color: AntaresColors.textDisabled,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Güncelle butonu
            SizedBox(
              width: 90,
              height: 36,
              child: ElevatedButton(
                onPressed: _isUpdating ? null : onUpdate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: color.withOpacity(0.15),
                  foregroundColor: color,
                  elevation: 0,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: color.withOpacity(0.3)),
                  ),
                ),
                child: Text(
                  onUpdate == null ? 'Bağlı Değil' : 'Güncelle',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // Boş Durum
  // ----------------------------------------------------------------
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_download_rounded,
            size: 64,
            color: AntaresColors.textDisabled.withOpacity(0.15),
          ),
          const SizedBox(height: 16),
          const Text(
            'Güncelleme bilgisi yok',
            style: TextStyle(
              color: AntaresColors.textDisabled,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Yukarıdaki butona tıklayarak\nGitHub\'daki son sürümü kontrol edin.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AntaresColors.textDisabled,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // Yardımcılar
  // ----------------------------------------------------------------
  String _formatDate(DateTime date) {
    return '${date.day}.${date.month.toString().padLeft(2, '0')}.${date.year}'
        '  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
