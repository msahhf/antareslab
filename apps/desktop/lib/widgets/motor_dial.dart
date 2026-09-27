/// Antares Studio - Interactive 360° Motor Control Dial
/// Futuristic circular dial for precise motor position control

import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/antares_theme.dart';

class MotorDial extends StatefulWidget {
  final double currentAngle;
  final double targetAngle;
  final bool isBusy;
  final bool isHomed;
  final ValueChanged<double>? onAngleSelected;
  final VoidCallback? onHomePressed;

  const MotorDial({
    super.key,
    this.currentAngle = 0,
    this.targetAngle = 0,
    this.isBusy = false,
    this.isHomed = false,
    this.onAngleSelected,
    this.onHomePressed,
  });

  @override
  State<MotorDial> createState() => _MotorDialState();
}

class _MotorDialState extends State<MotorDial>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _dragAngle = 0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.isBusy) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(MotorDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isBusy && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isBusy && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _angleToDegrees(double angle) {
    var degrees = angle * 180 / pi;
    if (degrees < 0) degrees += 360;
    return degrees;
  }

  double _snapToStep(double angle, double step) {
    return (angle / step).round() * step;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ring with ticks
          CustomPaint(
            size: const Size(280, 280),
            painter: _DialTicksPainter(
              accentColor: AntaresColors.cyan,
              isBusy: widget.isBusy,
            ),
          ),

          // Animated busy ring
          if (widget.isBusy)
            RotationTransition(
              turns: Tween(begin: 0.0, end: 1.0).animate(_controller),
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AntaresColors.cyan.withOpacity(0.3),
                    width: 2,
                  ),
                  gradient: SweepGradient(
                    colors: [
                      AntaresColors.cyan.withOpacity(0),
                      AntaresColors.cyan.withOpacity(0.8),
                      AntaresColors.cyan.withOpacity(0),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),

          // Current position indicator
          Transform.rotate(
            angle: widget.currentAngle * pi / 180,
            child: Container(
              width: 240,
              height: 240,
              alignment: Alignment.topCenter,
              child: Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AntaresColors.amber,
                      AntaresColors.amber.withOpacity(0.3),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: AntaresColors.amber.withOpacity(0.6),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Home indicator at 0°
          Positioned(
            top: 20,
            child: GestureDetector(
              onTap: widget.isBusy ? null : widget.onHomePressed,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isHomed
                      ? AntaresColors.emerald.withOpacity(0.2)
                      : AntaresColors.surfaceVariant,
                  border: Border.all(
                    color: widget.isHomed
                        ? AntaresColors.emerald
                        : AntaresColors.border,
                    width: 2,
                  ),
                  boxShadow: widget.isHomed
                      ? [
                          BoxShadow(
                            color: AntaresColors.emerald.withOpacity(0.4),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  Icons.home_rounded,
                  size: 18,
                  color: widget.isHomed
                      ? AntaresColors.emerald
                      : AntaresColors.textDisabled,
                ),
              ),
            ),
          ),

          // Drag interaction area
          GestureDetector(
            onPanStart: widget.isBusy
                ? null
                : (details) {
                    setState(() => _isDragging = true);
                  },
            onPanUpdate: widget.isBusy
                ? null
                : (details) {
                    final center = const Offset(140, 140);
                    final localPos = details.localPosition;
                    final angle = atan2(
                      localPos.dy - center.dy,
                      localPos.dx - center.dx,
                    );
                    setState(() => _dragAngle = _angleToDegrees(angle));
                  },
            onPanEnd: widget.isBusy
                ? null
                : (details) {
                    setState(() => _isDragging = false);
                    final snappedAngle = _snapToStep(_dragAngle, 45);
                    widget.onAngleSelected?.call(snappedAngle);
                  },
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AntaresColors.cyan.withOpacity(_isDragging ? 0.15 : 0.08),
                    AntaresColors.surface.withOpacity(0.9),
                  ],
                ),
                border: Border.all(
                  color: _isDragging
                      ? AntaresColors.cyan.withOpacity(0.5)
                      : AntaresColors.border.withOpacity(0.3),
                  width: 2,
                ),
                boxShadow: _isDragging
                    ? [
                        BoxShadow(
                          color: AntaresColors.cyan.withOpacity(0.3),
                          blurRadius: 30,
                          spreadRadius: -5,
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${(_isDragging ? _dragAngle : widget.currentAngle).toStringAsFixed(0)}°',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w700,
                      color: _isDragging
                          ? AntaresColors.cyan
                          : AntaresColors.textPrimary,
                      fontFamily: 'RobotoMono',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isDragging
                        ? 'RELEASE TO ROTATE'
                        : (widget.isBusy ? 'ROTATING...' : 'DRAG TO ROTATE'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: widget.isBusy
                          ? AntaresColors.cyan
                          : AntaresColors.textDisabled,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Drag cursor indicator
          if (_isDragging)
            Transform.rotate(
              angle: _dragAngle * pi / 180,
              child: Container(
                width: 220,
                height: 220,
                alignment: Alignment.topCenter,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AntaresColors.cyan,
                    boxShadow: [
                      BoxShadow(
                        color: AntaresColors.cyan.withOpacity(0.8),
                        blurRadius: 15,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DialTicksPainter extends CustomPainter {
  final Color accentColor;
  final bool isBusy;

  _DialTicksPainter({
    required this.accentColor,
    required this.isBusy,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 30;

    final majorTickPaint = Paint()
      ..color = accentColor.withOpacity(0.6)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final minorTickPaint = Paint()
      ..color = accentColor.withOpacity(0.2)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    // Draw ticks every 45 degrees
    for (int i = 0; i < 360; i += 45) {
      final angle = i * pi / 180;
      final isMajor = i % 90 == 0;
      final tickLength = isMajor ? 12.0 : 8.0;
      final paint = isMajor ? majorTickPaint : minorTickPaint;

      final start = Offset(
        center.dx + (radius - tickLength) * cos(angle),
        center.dy + (radius - tickLength) * sin(angle),
      );
      final end = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );

      canvas.drawLine(start, end, paint);

      // Draw degree labels for major ticks
      if (isMajor && i > 0) {
        final labelRadius = radius - 24;
        final labelPos = Offset(
          center.dx + labelRadius * cos(angle),
          center.dy + labelRadius * sin(angle),
        );

        // Simple text drawing would need TextPainter - skip for brevity
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is! _DialTicksPainter ||
        oldDelegate.isBusy != isBusy;
  }
}
