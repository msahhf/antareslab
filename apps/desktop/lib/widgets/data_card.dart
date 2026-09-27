// SPDX-License-Identifier: Apache-2.0

/// AntaresStudio IoT - Veri Kartı Widget'ı
///
/// Sensör verilerini (sıcaklık, nem, mesafe vb.) gösteren
/// kompakt kart bileşeni. Değer, birim, ikon ve mini sparkline içerir.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class DataCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color? accentColor;
  final List<double>? sparklineData;
  final String? subtitle;

  const DataCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    this.accentColor,
    this.sparklineData,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AntaresColors.primary;

    return Container(
      decoration: BoxDecoration(
        gradient: AntaresColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AntaresColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık satırı
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: AntaresColors.textDisabled,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Değer
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: AntaresColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                  shadows: [
                    Shadow(
                      color: accent.withOpacity(0.3),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  unit,
                  style: TextStyle(
                    color: accent.withOpacity(0.7),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          // Alt metin
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(
                color: AntaresColors.textDisabled,
                fontSize: 11,
              ),
            ),
          ],

          // Mini Sparkline
          if (sparklineData != null && sparklineData!.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 30,
              child: CustomPaint(
                size: const Size(double.infinity, 30),
                painter: _SparklinePainter(
                  data: sparklineData!,
                  color: accent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Mini sparkline çizici
class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _SparklinePainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final minVal = data.reduce((a, b) => a < b ? a : b);
    final maxVal = data.reduce((a, b) => a > b ? a : b);
    final range = maxVal - minVal;
    if (range == 0) return;

    final stepX = size.width / (data.length - 1);

    // Gradient dolgu yolu
    final fillPath = Path();
    final linePath = Path();

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = size.height - ((data[i] - minVal) / range) * size.height;

      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // Gradient dolgu
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.15), color.withOpacity(0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Çizgi
    final linePaint = Paint()
      ..color = color.withOpacity(0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);

    // Son nokta parlak daire
    final lastX = (data.length - 1) * stepX;
    final lastY = size.height - ((data.last - minVal) / range) * size.height;
    canvas.drawCircle(
      Offset(lastX, lastY),
      3,
      Paint()..color = color,
    );
    canvas.drawCircle(
      Offset(lastX, lastY),
      5,
      Paint()
        ..color = color.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return data != oldDelegate.data || color != oldDelegate.color;
  }
}
