/// AntaresStudio IoT - Ana Dashboard Ekranı
///
/// Canlı sensör verileri, ESP32-CAM canlı görüntüsü,
/// SD kart durumu ve hızlı kontrol butonları.
///
/// Bileşenler:
///   - Bağlantı durum çubuğu (üst)
///   - ESP32-CAM canlı görüntü kartı
///   - 2x2 sensör veri grid'i (Sıcaklık, Nem, Toprak Nem, Isıtıcı)
///   - Sistem durumu (Heap, PSRAM, Uptime, Motor, Fan)
///   - Hızlı kontrol butonları (Tarama, Fotoğraf, Motor Home, SD Aktarım)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';
import '../providers/scan_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/data_card.dart';
import '../widgets/glass_card.dart';
import '../widgets/status_indicator.dart' as si;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Sayfa giriş animasyonu
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _fadeController.forward();

    // İlk bağlantıyı başlat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeviceProvider>().connect();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<DeviceProvider, ScanProvider>(
      builder: (context, device, scan, _) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Üst boşluk
              const SliverToBoxAdapter(child: SizedBox(height: 8)),

              // Bağlantı durum kartı
              SliverToBoxAdapter(child: _buildConnectionCard(device)),

              // ESP32-CAM Canlı Görüntü
              SliverToBoxAdapter(child: _buildCameraCard(device)),

              // Tarama durumu (aktif, duraklatılmış veya pipeline çalışıyorsa)
              if (scan.isActive || scan.isPaused || scan.isPipelineRunning)
                SliverToBoxAdapter(child: _buildScanStatusCard(scan)),

              // Sensör Verileri Başlığı
              SliverToBoxAdapter(
                child: _buildSectionHeader('CANLI VERİLER', AntaresColors.primary),
              ),

              // 2x2 Sensör Grid
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.15,
                  children: [
                    DataCard(
                      icon: Icons.thermostat_rounded,
                      label: 'Sıcaklık',
                      value: device.sensorData.temperature.toStringAsFixed(1),
                      unit: '°C',
                      accentColor: AntaresColors.secondary,
                      sparklineData: device.temperatureHistory,
                      subtitle: 'Kapsül İçi',
                    ),
                    DataCard(
                      icon: Icons.water_drop_rounded,
                      label: 'Nem',
                      value: device.sensorData.humidity.toString(),
                      unit: '%',
                      accentColor: AntaresColors.info,
                      sparklineData: device.humidityHistory,
                      subtitle: 'Bağıl Nem',
                    ),
                    DataCard(
                      icon: Icons.grass_rounded,
                      label: 'Toprak Nem',
                      value: device.sensorData.soilMoisture.toString(),
                      unit: 'ADC',
                      accentColor: AntaresColors.primary,
                      subtitle: 'Analog Okuma',
                    ),
                    DataCard(
                      icon: Icons.local_fire_department_rounded,
                      label: 'Isıtıcı',
                      value: '${(device.sensorData.heaterPower / 2.55).toInt()}',
                      unit: '%',
                      accentColor: AntaresColors.warning,
                      subtitle: 'PWM Gücü',
                    ),
                  ],
                ),
              ),

              // Sistem Durumu
              SliverToBoxAdapter(
                child: _buildSectionHeader('SİSTEM', AntaresColors.primaryDim),
              ),
              SliverToBoxAdapter(child: _buildSystemCard(device)),

              // Hızlı Kontrol Butonları
              SliverToBoxAdapter(child: _buildQuickActions(device, scan)),

              // Alt boşluk
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        );
      },
    );
  }

  // ----------------------------------------------------------------
  // Bölüm Başlığı
  // ----------------------------------------------------------------
  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: AntaresColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(height: 1, color: AntaresColors.border),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // Bağlantı Durum Kartı
  // ----------------------------------------------------------------
  Widget _buildConnectionCard(DeviceProvider device) {
    final isConnected = device.isConnected;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        borderColor: isConnected
            ? AntaresColors.success.withOpacity(0.3)
            : AntaresColors.border,
        child: Row(
          children: [
            // Durum göstergesi
            si.StatusIndicator(
              state: _mapConnectionState(device.connectionState),
              label: 'KAPSÜL',
            ),
            const Spacer(),

            // Firmware versiyonu
            if (isConnected) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AntaresColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AntaresColors.primary.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.memory_rounded,
                        size: 14, color: AntaresColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'v${device.firmwareVersion}',
                      style: const TextStyle(
                        color: AntaresColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // Mod badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: device.sensorData.mode == 'STUDIO'
                      ? AntaresColors.info.withOpacity(0.1)
                      : AntaresColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  device.sensorData.mode,
                  style: TextStyle(
                    color: device.sensorData.mode == 'STUDIO'
                        ? AntaresColors.info
                        : AntaresColors.success,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],

            const SizedBox(width: 8),

            // Bağlan/Kes butonu
            _buildMiniButton(
              icon: isConnected ? Icons.link_off_rounded : Icons.link_rounded,
              label: isConnected ? 'Kes' : 'Bağlan',
              color: isConnected ? AntaresColors.textDisabled : AntaresColors.primary,
              onTap: () {
                if (isConnected) {
                  device.disconnect();
                } else {
                  device.connect();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // ESP32-CAM Canlı Görüntü Kartı
  // ----------------------------------------------------------------
  Widget _buildCameraCard(DeviceProvider device) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          gradient: AntaresColors.cardGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AntaresColors.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Başlık
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AntaresColors.error.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.videocam_rounded,
                        color: AntaresColors.error, size: 16),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'ESP32-CAM',
                    style: TextStyle(
                      color: AntaresColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Canlı badge
                  if (device.isConnected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AntaresColors.error.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, color: AntaresColors.error, size: 6),
                          SizedBox(width: 4),
                          Text(
                            'CANLI',
                            style: TextStyle(
                              color: AntaresColors.error,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const Spacer(),

                  // Fotoğraf çek butonu
                  IconButton(
                    icon: const Icon(Icons.camera_alt_rounded,
                        color: AntaresColors.textSecondary, size: 20),
                    onPressed: device.isConnected
                        ? () => _handleCapture(device)
                        : null,
                    tooltip: 'Fotoğraf Çek',
                    style: IconButton.styleFrom(
                      backgroundColor: AntaresColors.surfaceElevated,
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                ],
              ),
            ),

            // Kamera Görüntü Alanı
            Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AntaresColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: device.isConnected
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            // MJPEG Stream
                            Image.network(
                              'http://${DeviceProvider.espHost}:81/api/stream',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return _buildCameraPlaceholder(
                                    'Stream yüklenemedi', Icons.error_outline_rounded);
                              },
                              loadingBuilder: (_, child, progress) {
                                if (progress == null) return child;
                                return _buildCameraPlaceholder(
                                    'Akış bağlanıyor...', Icons.linked_camera_rounded);
                              },
                            ),

                            // SD kart durumu overlay
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.sd_card_rounded,
                                      size: 12,
                                      color: device.espStatus?.sdCard == true
                                          ? AntaresColors.success
                                          : AntaresColors.error,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      device.espStatus?.sdCard == true ? 'SD OK' : 'SD YOK',
                                      style: const TextStyle(
                                        color: AntaresColors.textSecondary,
                                        fontSize: 10,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Çözünürlük badge
                            Positioned(
                              bottom: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'AP: ${DeviceProvider.espHost}  |  1600×1200',
                                  style: const TextStyle(
                                    color: AntaresColors.textDisabled,
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.videocam_off_rounded,
                                  size: 40,
                                  color: AntaresColors.textDisabled.withOpacity(0.3)),
                              const SizedBox(height: 8),
                              const Text(
                                'Kapsül bağlı değil',
                                style: TextStyle(
                                  color: AntaresColors.textDisabled,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Wi-Fi: ANTARES_KAPSUL_LAB',
                                style: TextStyle(
                                  color: AntaresColors.textDisabled,
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPlaceholder(String text, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [AntaresColors.surfaceLight, AntaresColors.background],
          radius: 0.8,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AntaresColors.primary.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text(
              text,
              style: const TextStyle(color: AntaresColors.textDisabled, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // Tarama Durumu Kartı (aktif, duraklatılmış, pipeline)
  // ----------------------------------------------------------------
  Widget _buildScanStatusCard(ScanProvider scan) {
    final isPaused = scan.isPaused;
    final isPipeline = scan.isPipelineRunning;
    final accentColor = isPaused
        ? AntaresColors.warning
        : isPipeline
            ? AntaresColors.info
            : AntaresColors.primary;
    final statusLabel = isPaused
        ? 'TARAMA DURAKLATILDI'
        : isPipeline
            ? 'PİPELİNE ÇALIŞIYOR'
            : 'TARAMA AKTİF';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          gradient: AntaresColors.cardGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accentColor.withOpacity(0.3), width: 1),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isPaused ? Icons.pause_circle_rounded
                    : isPipeline ? Icons.precision_manufacturing_rounded
                    : Icons.radar_rounded,
                  color: accentColor, size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                if (!isPaused)
                  Text(
                    isPipeline
                        ? '${scan.pipelineStatus?.progress ?? 0}%'
                        : '${scan.progressPercent}%',
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // İlerleme çubuğu
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: isPipeline
                    ? (scan.pipelineStatus?.progress ?? 0) / 100
                    : scan.progressPercent / 100,
                backgroundColor: AntaresColors.surface,
                color: accentColor,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              scan.statusMessage,
              style: const TextStyle(
                color: AntaresColors.textSecondary,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Duraklatılmışsa Resume butonu
                if (isPaused)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _buildMiniButton(
                      icon: Icons.play_arrow_rounded,
                      label: 'Devam Et',
                      color: AntaresColors.success,
                      onTap: () => scan.resumeScan(),
                    ),
                  ),
                // İptal butonu
                _buildMiniButton(
                  icon: Icons.stop_rounded,
                  label: 'İptal',
                  color: AntaresColors.error,
                  onTap: () => isPipeline ? scan.cancelPipeline() : scan.cancelScan(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // Sistem Durumu Kartı
  // ----------------------------------------------------------------
  Widget _buildSystemCard(DeviceProvider device) {
    final data = device.sensorData;
    final esp = device.espStatus;
    final uptimeStr = _formatUptime(esp?.uptimeSec ?? 0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          gradient: AntaresColors.cardGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AntaresColors.border, width: 1),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSystemRow(
                Icons.memory_rounded, 'Heap', _formatBytes(esp?.heapFree ?? 0)),
            const SizedBox(height: 10),
            _buildSystemRow(
                Icons.sd_storage_rounded, 'PSRAM', _formatBytes(esp?.psramFree ?? 0)),
            const SizedBox(height: 10),
            _buildSystemRow(
                Icons.timer_rounded, 'Uptime', uptimeStr),
            const SizedBox(height: 10),
            _buildSystemRow(
                Icons.rotate_right_rounded, 'Motor',
                'Pos: ${data.motorPosition}  |  ${data.isHomed ? "HOME" : "?"}',
                valueColor: data.isHomed
                    ? AntaresColors.success
                    : AntaresColors.textDisabled),
            const SizedBox(height: 10),
            _buildSystemRow(
                Icons.air_rounded, 'Fanlar',
                'SLY: ${data.fanSly ? "AKTİF" : "KAPALI"}  |  DZ: ${data.fanDz ? "AKTİF" : "KAPALI"}',
                valueColor: (data.fanSly || data.fanDz)
                    ? AntaresColors.info
                    : AntaresColors.textDisabled),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AntaresColors.textDisabled),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: AntaresColors.textDisabled,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AntaresColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------
  // Hızlı Kontrol Butonları
  // ----------------------------------------------------------------
  Widget _buildQuickActions(DeviceProvider device, ScanProvider scan) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.radar_rounded,
                  label: '360° Tarama\nBaşlat',
                  color: AntaresColors.primary,
                  onTap: device.isConnected && !scan.isActive
                      ? () => scan.startScan()
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.camera_alt_rounded,
                  label: 'Tek\nFotoğraf',
                  color: AntaresColors.info,
                  onTap: device.isConnected
                      ? () => _handleCapture(device)
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.home_rounded,
                  label: 'Motor\nHome',
                  color: AntaresColors.secondary,
                  onTap: device.isConnected
                      ? () => device.motorHome()
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.sd_card_rounded,
                  label: 'SD Kart\nAktarım',
                  color: AntaresColors.warning,
                  onTap: device.isConnected && !scan.isActive
                      ? () => scan.transferFromSD()
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    final isDisabled = onTap == null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isDisabled
              ? AntaresColors.surface
              : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDisabled
                ? AntaresColors.border
                : color.withOpacity(0.25),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 28,
              color: isDisabled
                  ? AntaresColors.textDisabled.withOpacity(0.3)
                  : color,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDisabled
                    ? AntaresColors.textDisabled.withOpacity(0.5)
                    : AntaresColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // Mini buton (bağlan/kes)
  // ----------------------------------------------------------------
  Widget _buildMiniButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // Fotoğraf Çekimi
  // ----------------------------------------------------------------
  void _handleCapture(DeviceProvider device) async {
    final jpeg = await device.capturePhoto();
    if (jpeg != null && mounted) {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: AntaresColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Image.memory(jpeg, fit: BoxFit.contain),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(jpeg.length / 1024).toStringAsFixed(0)} KB',
                      style: const TextStyle(
                        color: AntaresColors.textDisabled,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Kapat'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  // ----------------------------------------------------------------
  // Yardımcılar
  // ----------------------------------------------------------------
  si.ConnectionState _mapConnectionState(DeviceConnectionState state) {
    switch (state) {
      case DeviceConnectionState.connected:
        return si.ConnectionState.connected;
      case DeviceConnectionState.connecting:
      case DeviceConnectionState.reconnecting:
        return si.ConnectionState.connecting;
      default:
        return si.ConnectionState.disconnected;
    }
  }

  String _formatUptime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    return '${hours}h ${minutes}m ${secs}s';
  }

  String _formatBytes(int bytes) {
    if (bytes > 1000000) return '${(bytes / 1000000).toStringAsFixed(1)} MB';
    if (bytes > 1000) return '${(bytes / 1000).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}
