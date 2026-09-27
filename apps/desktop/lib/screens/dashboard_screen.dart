// SPDX-License-Identifier: Apache-2.0

/// Antares Studio - Telemetry Dashboard (Sci-Fi Archaeology Capsule Interface)
/// Real-time sensor vitals with glassmorphism cards and neon gauges

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';
import '../providers/scan_provider.dart';
import '../theme/antares_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/telemetry_gauge.dart';
import '../widgets/status_indicator.dart';
import '../widgets/action_button.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    // İlk bağlantıyı başlat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeviceProvider>().connect();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer2<DeviceProvider, ScanProvider>(
      builder: (context, device, scan, _) {
        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // SYSTEM STATUS HEADER
            SliverToBoxAdapter(
              child: _buildSystemStatusHeader(device, scan),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // TELEMETRY GAUGES
            SliverToBoxAdapter(
              child: _buildTelemetrySection(device),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // ACTUATOR STATUS
            SliverToBoxAdapter(
              child: _buildActuatorSection(device),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),

            // QUICK ACTIONS
            SliverToBoxAdapter(
              child: _buildQuickActionsSection(device, scan),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        );
      },
    );
  }

  // ----------------------------------------------------------------
  // SYSTEM STATUS HEADER - Large animated status indicator
  // ----------------------------------------------------------------
  Widget _buildSystemStatusHeader(DeviceProvider device, ScanProvider scan) {
    final isConnected = device.isConnected;
    final hasError = device.connectionState == DeviceConnectionState.error;
    final isScanning = scan.isActive || scan.isPipelineRunning;
    final isBusy = scan.isActive || scan.isPipelineRunning || scan.isPaused;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (hasError) {
      statusColor = AntaresColors.rose;
      statusText = 'CONNECTION ERROR';
      statusIcon = Icons.error_outline_rounded;
    } else if (isScanning) {
      statusColor = AntaresColors.cyan;
      statusText = 'SCANNING ACTIVE';
      statusIcon = Icons.radar_rounded;
    } else if (isConnected) {
      statusColor = AntaresColors.emerald;
      statusText = 'SYSTEM ONLINE';
      statusIcon = Icons.check_circle_rounded;
    } else {
      statusColor = AntaresColors.amber;
      statusText = 'STANDBY';
      statusIcon = Icons.power_settings_new_rounded;
    }

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GlassCard(
            padding: const EdgeInsets.all(20),
            borderColor: statusColor.withOpacity(0.3),
            child: Column(
              children: [
                Row(
                  children: [
                    // Animated status ring
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: statusColor.withOpacity(0.3),
                          width: 2,
                        ),
                        boxShadow: isBusy ? [
                          BoxShadow(
                            color: statusColor.withOpacity(_pulseAnimation.value * 0.4),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ] : null,
                      ),
                      child: Center(
                        child: Icon(
                          statusIcon,
                          size: 28,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isConnected
                                ? 'Capsule v${device.firmwareVersion} • ${device.sensorData.mode}'
                                : device.statusMessage,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AntaresColors.textSecondary,
                            ),
                          ),
                          if (isBusy) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: scan.isPipelineRunning
                                    ? (scan.pipelineStatus?.progress ?? 0) / 100
                                    : scan.progressPercent / 100,
                                backgroundColor: AntaresColors.border.withOpacity(0.3),
                                color: statusColor,
                                minHeight: 4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Connection button
                    _buildConnectionButton(device),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectionButton(DeviceProvider device) {
    final isConnected = device.isConnected;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => isConnected ? device.disconnect() : device.connect(),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isConnected
                ? AntaresColors.rose.withOpacity(0.1)
                : AntaresColors.cyan.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isConnected
                  ? AntaresColors.rose.withOpacity(0.3)
                  : AntaresColors.cyan.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isConnected ? Icons.link_off_rounded : Icons.link_rounded,
                size: 16,
                color: isConnected ? AntaresColors.rose : AntaresColors.cyan,
              ),
              const SizedBox(width: 6),
              Text(
                isConnected ? 'DISCONNECT' : 'CONNECT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isConnected ? AntaresColors.rose : AntaresColors.cyan,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // TELEMETRY GAUGES - Circular animated indicators
  // ----------------------------------------------------------------
  Widget _buildTelemetrySection(DeviceProvider device) {
    final data = device.sensorData;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('LIVE TELEMETRY', AntaresColors.cyan),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TelemetryGauge(
                value: data.temperature,
                min: -10,
                max: 60,
                label: 'TEMPERATURE',
                unit: '°C',
                accentColor: AntaresColors.amber,
                icon: Icons.thermostat_rounded,
              ),
              TelemetryGauge(
                value: data.humidity.toDouble(),
                min: 0,
                max: 100,
                label: 'HUMIDITY',
                unit: '%RH',
                accentColor: AntaresColors.cyan,
                icon: Icons.water_drop_rounded,
              ),
              TelemetryGauge(
                value: data.soilMoisture.toDouble(),
                min: 0,
                max: 1024,
                label: 'SOIL MOISTURE',
                unit: 'ADC',
                accentColor: AntaresColors.violet,
                icon: Icons.grass_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // ACTUATOR STATUS - Heater and fans
  // ----------------------------------------------------------------
  Widget _buildActuatorSection(DeviceProvider device) {
    final data = device.sensorData;
    final heaterPercent = (data.heaterPower / 2.55).round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('ACTUATORS', AntaresColors.amber),
          const SizedBox(height: 16),
          Row(
            children: [
              // Heater control
              Expanded(
                child: _buildActuatorCard(
                  'HEATER',
                  Icons.local_fire_department_rounded,
                  heaterPercent > 0 ? AntaresColors.amber : AntaresColors.textDisabled,
                  heaterPercent > 0,
                  '$heaterPercent% POWER',
                ),
              ),
              const SizedBox(width: 12),
              // Sly Fan
              Expanded(
                child: _buildActuatorCard(
                  'SUCTION FAN',
                  Icons.air_rounded,
                  data.fanSly ? AntaresColors.cyan : AntaresColors.textDisabled,
                  data.fanSly,
                  data.fanSly ? 'ACTIVE' : 'OFF',
                ),
              ),
              const SizedBox(width: 12),
              // Dz Fan
              Expanded(
                child: _buildActuatorCard(
                  'DISPERSION FAN',
                  Icons.wind_power_rounded,
                  data.fanDz ? AntaresColors.emerald : AntaresColors.textDisabled,
                  data.fanDz,
                  data.fanDz ? 'ACTIVE' : 'OFF',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActuatorCard(
    String label,
    IconData icon,
    Color color,
    bool isActive,
    String status,
  ) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderColor: color.withOpacity(isActive ? 0.4 : 0.2),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.15),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: color.withOpacity(0.3),
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              size: 22,
              color: color,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AntaresColors.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            status,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // QUICK ACTIONS
  // ----------------------------------------------------------------
  Widget _buildQuickActionsSection(DeviceProvider device, ScanProvider scan) {
    final isBusy = scan.isActive || scan.isPipelineRunning;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('QUICK ACTIONS', AntaresColors.emerald),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ActionButton(
                  label: 'START 360° SCAN',
                  icon: Icons.radar_rounded,
                  onPressed: device.isConnected && !isBusy
                      ? () => scan.startScan()
                      : null,
                  isLoading: scan.isActive && !scan.isPipelineRunning,
                  isDisabled: !device.isConnected || isBusy,
                  accentColor: AntaresColors.cyan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ActionButton(
                  label: 'CAPTURE PHOTO',
                  icon: Icons.camera_alt_rounded,
                  onPressed: device.isConnected && !isBusy
                      ? () => _capturePhoto(device)
                      : null,
                  isDisabled: !device.isConnected || isBusy,
                  accentColor: AntaresColors.violet,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ActionButton(
                  label: 'MOTOR HOME',
                  icon: Icons.home_rounded,
                  onPressed: device.isConnected && !isBusy
                      ? () => device.motorHome()
                      : null,
                  isDisabled: !device.isConnected || isBusy,
                  accentColor: AntaresColors.amber,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // UTILITY WIDGETS
  // ----------------------------------------------------------------
  Widget _buildSectionTitle(String title, Color accentColor) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: accentColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AntaresColors.textSecondary,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: AntaresColors.border.withOpacity(0.3),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------
  // ACTIONS
  // ----------------------------------------------------------------
  Future<void> _capturePhoto(DeviceProvider device) async {
    final jpeg = await device.capturePhoto();
    if (jpeg != null && mounted) {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: AntaresColors.surface.withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AntaresColors.cyan.withOpacity(0.3),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  child: Image.memory(jpeg, fit: BoxFit.contain),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.image_rounded,
                            size: 16,
                            color: AntaresColors.cyan.withOpacity(0.7),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(jpeg.length / 1024).toStringAsFixed(0)} KB',
                            style: const TextStyle(
                              color: AntaresColors.textSecondary,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('CLOSE'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  DeviceConnectionStatus _mapConnectionState(DeviceConnectionState state) {
    switch (state) {
      case DeviceConnectionState.connected:
        return DeviceConnectionStatus.connected;
      case DeviceConnectionState.connecting:
      case DeviceConnectionState.reconnecting:
        return DeviceConnectionStatus.connecting;
      default:
        return DeviceConnectionStatus.disconnected;
    }
  }
}
