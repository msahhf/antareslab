/// Antares Studio - Animated Circular Telemetry Gauge
/// Sci-fi style circular progress indicator with neon glow

import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/antares_theme.dart';

class TelemetryGauge extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final String label;
  final String unit;
  final Color accentColor;
  final IconData icon;
  final double size;

  const TelemetryGauge({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 100,
    required this.label,
    required this.unit,
    required this.accentColor,
    required this.icon,
    this.size = 140,
  });

  @override
  State<TelemetryGauge> createState() => _TelemetryGaugeState();
}

class _TelemetryGaugeState extends State<TelemetryGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _valueAnimation;
  double _displayValue = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _valueAnimation = Tween<double>(
      begin: 0,
      end: widget.value,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    _controller.forward();
  }

  @override
  void didUpdateWidget(TelemetryGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _valueAnimation = Tween<double>(
        begin: _displayValue,
        end: widget.value,
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _percentage {
    final range = widget.max - widget.min;
    if (range == 0) return 0;
    return ((widget.value - widget.min) / range).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _valueAnimation,
      builder: (context, child) {
        _displayValue = _valueAnimation.value;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.accentColor.withOpacity(0.15),
                blurRadius: 30,
                spreadRadius: -5,
              ),
            ],
          ),
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _GaugePainter(
              percentage: _percentage,
              accentColor: widget.accentColor,
              backgroundColor: AntaresColors.border,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.icon,
                    color: widget.accentColor.withOpacity(0.8),
                    size: 20,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _displayValue.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: widget.accentColor,
                      fontFamily: 'RobotoMono',
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    widget.unit,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AntaresColors.textDisabled,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AntaresColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double percentage;
  final Color accentColor;
  final Color backgroundColor;

  _GaugePainter({
    required this.percentage,
    required this.accentColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    final strokeWidth = 8.0;

    // Background arc
    final bgPaint = Paint()
      ..color = backgroundColor.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi * 0.75,
      pi * 1.5,
      false,
      bgPaint,
    );

    // Progress arc with gradient
    final gradient = SweepGradient(
      colors: [
        accentColor.withOpacity(0.3),
        accentColor,
        accentColor.withOpacity(0.8),
      ],
      stops: const [0.0, 0.5, 1.0],
      startAngle: pi * 0.75,
      endAngle: pi * 0.75 + pi * 1.5,
    );

    final progressPaint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi * 0.75,
      pi * 1.5 * percentage,
      false,
      progressPaint,
    );

    // Glow effect at end of progress
    if (percentage > 0) {
      final angle = pi * 0.75 + pi * 1.5 * percentage;
      final endX = center.dx + radius * cos(angle);
      final endY = center.dy + radius * sin(angle);

      final glowPaint = Paint()
        ..color = accentColor.withOpacity(0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      canvas.drawCircle(
        Offset(endX, endY),
        strokeWidth / 2,
        glowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.percentage != percentage ||
        oldDelegate.accentColor != accentColor;
  }
}
