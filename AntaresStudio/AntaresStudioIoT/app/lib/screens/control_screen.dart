/// Antares Studio - Control Center Screen
/// Motor controls, mode selector, and 360° scan interface

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';
import '../providers/scan_provider.dart';
import '../theme/antares_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/motor_dial.dart';
import '../widgets/segmented_control.dart';
import '../widgets/action_button.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  late AnimationController _modeAnimController;

  @override
  void initState() {
    super.initState();
    _modeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _modeAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer2<DeviceProvider, ScanProvider>(
      builder: (context, device, scan, _) {
        final isManual = device.sensorData.mode == 'MANUEL';
        if (isManual) {
          _modeAnimController.forward();
        } else {
          _modeAnimController.reverse();
        }

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // Mode Selector
            SliverToBoxAdapter(
              child: _buildModeSelector(device),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // Motor Control Dial
            SliverToBoxAdapter(
              child: _buildMotorControlSection(device, scan),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // Scan Controls
            SliverToBoxAdapter(
              child: _buildScanControlSection(device, scan),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // Manual Rotation Controls
            SliverToBoxAdapter(
              child: _buildManualRotationSection(device, scan),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        );
      },
    );
  }

  Widget _buildModeSelector(DeviceProvider device) {
    final isManual = device.sensorData.mode == 'MANUEL';
    final canToggle = device.isConnected;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('OPERATION MODE', AntaresColors.violet),
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                SegmentedControl<String>(
                  value: isManual ? 'MANUAL' : 'AUTO',
                  options: const [
                    SegmentedOption(
                      value: 'AUTO',
                      label: 'AUTONOMOUS',
                      icon: Icons.auto_mode_rounded,
                    ),
                    SegmentedOption(
                      value: 'MANUAL',
                      label: 'MANUAL',
                      icon: Icons.touch_app_rounded,
                    ),
                  ],
                  onChanged: canToggle
                      ? (value) async {
                          HapticFeedback.lightImpact();
                          if (value == 'AUTO') {
                            await device.resumeAutonomous();
                          } else {
                            await device.pauseAutonomous();
                          }
                        }
                      : (_) {},
                  activeColor: isManual ? AntaresColors.amber : AntaresColors.cyan,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      isManual ? Icons.info_outline_rounded : Icons.schedule_rounded,
                      size: 16,
                      color: AntaresColors.textDisabled,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isManual
                            ? 'Manual mode: Direct control enabled. Use dial or buttons to rotate.'
                            : 'Auto mode: System runs autonomously with 5-minute interval scans.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AntaresColors.textDisabled,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMotorControlSection(DeviceProvider device, ScanProvider scan) {
    final isBusy = scan.isActive || scan.isPipelineRunning;
    final data = device.sensorData;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('MOTOR CONTROL', AntaresColors.cyan),
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Motor dial
                MotorDial(
                  currentAngle: data.motorPosition.toDouble(),
                  isBusy: isBusy || !device.isConnected,
                  isHomed: data.isHomed,
                  onAngleSelected: (angle) async {
                    HapticFeedback.mediumImpact();
                    await device.sendArduinoCommand('R${angle.toInt()}');
                  },
                  onHomePressed: () async {
                    HapticFeedback.heavyImpact();
                    await device.motorHome();
                  },
                ),
                const SizedBox(height: 20),
                // Motor info row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildMotorInfoChip(
                      'POSITION',
                      '${data.motorPosition}°',
                      AntaresColors.cyan,
                    ),
                    const SizedBox(width: 16),
                    _buildMotorInfoChip(
                      'STATUS',
                      data.isHomed ? 'HOMED' : 'UNHOMED',
                      data.isHomed ? AntaresColors.emerald : AntaresColors.amber,
                    ),
                    const SizedBox(width: 16),
                    _buildMotorInfoChip(
                      'MODE',
                      device.sensorData.mode,
                      device.sensorData.mode == 'MANUEL'
                          ? AntaresColors.amber
                          : AntaresColors.violet,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMotorInfoChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: color.withOpacity(0.7),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanControlSection(DeviceProvider device, ScanProvider scan) {
    final isBusy = scan.isActive || scan.isPipelineRunning;
    final isPaused = scan.isPaused;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('360° SCAN', AntaresColors.amber),
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Scan configuration
                Row(
                  children: [
                    Expanded(
                      child: _buildScanParamField(
                        'PHOTOS',
                        scan.numPhotos.toString(),
                        AntaresColors.cyan,
                        onTap: () => _showPhotoCountDialog(scan),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildScanParamField(
                        'STEP ANGLE',
                        '${scan.stepAngle.toStringAsFixed(0)}°',
                        AntaresColors.amber,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildScanParamField(
                        'STABILIZE',
                        '${scan.stabilizationDelayMs}ms',
                        AntaresColors.emerald,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Action buttons
                if (isPaused)
                  Row(
                    children: [
                      Expanded(
                        child: ActionButton(
                          label: 'RESUME SCAN',
                          icon: Icons.play_arrow_rounded,
                          onPressed: () => scan.resumeScan(),
                          accentColor: AntaresColors.emerald,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ActionButton(
                          label: 'CANCEL',
                          icon: Icons.stop_rounded,
                          onPressed: () => scan.cancelScan(),
                          accentColor: AntaresColors.rose,
                        ),
                      ),
                    ],
                  )
                else if (isBusy && scan.isPipelineRunning)
                  ActionButton(
                    label: 'CANCEL PIPELINE',
                    icon: Icons.stop_rounded,
                    onPressed: () => scan.cancelPipeline(),
                    accentColor: AntaresColors.rose,
                  )
                else if (isBusy)
                  ActionButton(
                    label: 'SCAN IN PROGRESS...',
                    icon: Icons.radar_rounded,
                    onPressed: null,
                    isLoading: true,
                    accentColor: AntaresColors.cyan,
                  )
                else
                  ActionButton(
                    label: 'START 360° SCAN',
                    icon: Icons.radar_rounded,
                    onPressed: device.isConnected
                        ? () => _startScanWithConfirm(scan)
                        : null,
                    accentColor: AntaresColors.cyan,
                  ),
                // Progress bar
                if (isBusy && !scan.isPipelineRunning) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: scan.progressPercent / 100,
                      backgroundColor: AntaresColors.border.withOpacity(0.3),
                      color: AntaresColors.cyan,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Step ${scan.currentStep}/${scan.totalSteps}: ${scan.statusMessage}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AntaresColors.textSecondary,
                    ),
                  ),
                ],
                // Pipeline progress
                if (scan.isPipelineRunning) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (scan.pipelineStatus?.progress ?? 0) / 100,
                      backgroundColor: AntaresColors.border.withOpacity(0.3),
                      color: AntaresColors.violet,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pipeline: ${scan.pipelineStatus?.currentStep ?? "Starting"} (${scan.pipelineStatus?.progress ?? 0}%)',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AntaresColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanParamField(String label, String value, Color color, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: color.withOpacity(0.6),
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
                fontFamily: 'RobotoMono',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualRotationSection(DeviceProvider device, ScanProvider scan) {
    final isBusy = scan.isActive || scan.isPipelineRunning;
    final canControl = device.isConnected && !isBusy;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('PRESET ROTATIONS', AntaresColors.emerald),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1,
            children: [0, 45, 90, 135, 180, 225, 270, 315].map((angle) {
              return _buildAngleButton(
                angle: angle,
                onTap: canControl
                    ? () async {
                        HapticFeedback.lightImpact();
                        await device.sendArduinoCommand('R$angle');
                      }
                    : null,
                accentColor: angle == 0 ? AntaresColors.emerald : AntaresColors.cyan,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAngleButton({
    required int angle,
    required VoidCallback? onTap,
    required Color accentColor,
  }) {
    final isHome = angle == 0;
    final isDisabled = onTap == null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isDisabled
                ? AntaresColors.surface.withOpacity(0.5)
                : accentColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDisabled
                  ? AntaresColors.border.withOpacity(0.3)
                  : accentColor.withOpacity(0.4),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isHome ? Icons.home_rounded : Icons.rotate_right_rounded,
                size: 18,
                color: isDisabled ? AntaresColors.textDisabled : accentColor,
              ),
              const SizedBox(height: 4),
              Text(
                '$angle°',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDisabled ? AntaresColors.textDisabled : accentColor,
                  fontFamily: 'RobotoMono',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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

  void _startScanWithConfirm(ScanProvider scan) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AntaresColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AntaresColors.cyan.withOpacity(0.3)),
        ),
        title: Row(
          children: [
            Icon(Icons.radar_rounded, color: AntaresColors.cyan),
            const SizedBox(width: 12),
            const Text(
              'Start 360° Scan?',
              style: TextStyle(color: AntaresColors.textPrimary),
            ),
          ],
        ),
        content: Text(
          'This will capture ${scan.numPhotos} photos at ${scan.stepAngle.toStringAsFixed(0)}° intervals.',
          style: const TextStyle(color: AntaresColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              scan.startScan();
            },
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('START SCAN'),
            style: FilledButton.styleFrom(
              backgroundColor: AntaresColors.cyan,
              foregroundColor: AntaresColors.textInverse,
            ),
          ),
        ],
      ),
    );
  }

  void _showPhotoCountDialog(ScanProvider scan) {
    final options = [4, 8, 12, 16, 24, 36];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AntaresColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AntaresColors.cyan.withOpacity(0.3)),
        ),
        title: const Text(
          'Photo Count',
          style: TextStyle(color: AntaresColors.textPrimary),
        ),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((count) {
            final isSelected = scan.numPhotos == count;
            return ChoiceChip(
              label: Text('$count'),
              selected: isSelected,
              onSelected: (_) {
                scan.numPhotos = count;
                scan.stepAngle = 360.0 / count;
                Navigator.pop(ctx);
              },
              backgroundColor: AntaresColors.surfaceVariant,
              selectedColor: AntaresColors.cyan.withOpacity(0.2),
              labelStyle: TextStyle(
                color: isSelected ? AntaresColors.cyan : AntaresColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
              side: BorderSide(
                color: isSelected ? AntaresColors.cyan : AntaresColors.border,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
