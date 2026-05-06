/// Antares Studio - Sci-Fi Segmented Control (Mode Selector)
/// Futuristic pill-style segmented control with neon glow

import 'package:flutter/material.dart';
import '../theme/antares_theme.dart';

class SegmentedControl<T> extends StatelessWidget {
  final T value;
  final List<SegmentedOption<T>> options;
  final ValueChanged<T> onChanged;
  final Color activeColor;
  final double height;

  const SegmentedControl({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.activeColor = AntaresColors.cyan,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AntaresColors.surface.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AntaresColors.border.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Row(
        children: options.map((option) {
          final isSelected = value == option.value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(option.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                          colors: [
                            activeColor.withOpacity(0.3),
                            activeColor.withOpacity(0.1),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        )
                      : null,
                  color: isSelected ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(
                          color: activeColor.withOpacity(0.5),
                          width: 1.5,
                        )
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: activeColor.withOpacity(0.2),
                            blurRadius: 12,
                            spreadRadius: -2,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (option.icon != null) ...[
                        Icon(
                          option.icon,
                          size: 16,
                          color: isSelected
                              ? activeColor
                              : AntaresColors.textDisabled,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        option.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected
                              ? activeColor
                              : AntaresColors.textDisabled,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class SegmentedOption<T> {
  final T value;
  final String label;
  final IconData? icon;

  const SegmentedOption({
    required this.value,
    required this.label,
    this.icon,
  });
}
