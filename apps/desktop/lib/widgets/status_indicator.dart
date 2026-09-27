// SPDX-License-Identifier: Apache-2.0

/// AntaresStudio IoT - Durum Göstergesi Widget'ı
///
/// Bağlantı durumu, sensör durumu gibi bilgileri küçük
/// animasyonlu nokta + metin ile gösteren yeniden kullanılabilir bileşen.

import 'package:flutter/material.dart';
import '../theme/antares_theme.dart';

enum DeviceConnectionStatus {
  connected,
  connecting,
  disconnected,
}

class StatusIndicator extends StatefulWidget {
  final DeviceConnectionStatus state;
  final String label;

  const StatusIndicator({
    super.key,
    required this.state,
    required this.label,
  });

  @override
  State<StatusIndicator> createState() => _StatusIndicatorState();
}

class _StatusIndicatorState extends State<StatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.state == DeviceConnectionStatus.connecting) {
      _pulseController.repeat(reverse: true);
    } else if (widget.state == DeviceConnectionStatus.connected) {
      _pulseController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(StatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state != oldWidget.state) {
      if (widget.state == DeviceConnectionStatus.connecting) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.value = widget.state == DeviceConnectionStatus.connected ? 1.0 : 0.4;
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color get _color {
    switch (widget.state) {
      case DeviceConnectionStatus.connected:
        return AntaresColors.success;
      case DeviceConnectionStatus.connecting:
        return AntaresColors.warning;
      case DeviceConnectionStatus.disconnected:
        return AntaresColors.error;
    }
  }

  String get _statusText {
    switch (widget.state) {
      case DeviceConnectionStatus.connected:
        return 'Bağlı';
      case DeviceConnectionStatus.connecting:
        return 'Bağlanıyor...';
      case DeviceConnectionStatus.disconnected:
        return 'Bağlantı Yok';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _color.withOpacity(_pulseAnimation.value),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _color.withOpacity(_pulseAnimation.value * 0.5),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.label,
              style: const TextStyle(
                color: AntaresColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.8,
              ),
            ),
            Text(
              _statusText,
              style: TextStyle(
                color: _color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
