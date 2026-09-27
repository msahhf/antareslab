// SPDX-License-Identifier: Apache-2.0

/// Antares Studio - Glowing Action Button
/// Large, satisfying buttons with neon glow effects for primary actions

import 'package:flutter/material.dart';
import '../theme/antares_theme.dart';

class ActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final Color accentColor;
  final double width;
  final double height;

  const ActionButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.accentColor = AntaresColors.cyan,
    this.width = double.infinity,
    this.height = 56,
  });

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    if (widget.isLoading) {
      _glowController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(ActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading && !_glowController.isAnimating) {
      _glowController.repeat(reverse: true);
    } else if (!widget.isLoading && _glowController.isAnimating) {
      _glowController.stop();
      _glowController.value = 0.5;
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = !widget.isDisabled && !widget.isLoading;

    return MouseRegion(
      onEnter: isActive ? (_) => setState(() => _isHovered = true) : null,
      onExit: isActive ? (_) => setState(() => _isHovered = false) : null,
      child: GestureDetector(
        onTapDown: isActive ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: isActive
            ? (_) {
                setState(() => _isPressed = false);
                widget.onPressed?.call();
              }
            : null,
        onTapCancel: isActive ? () => setState(() => _isPressed = false) : null,
        child: AnimatedBuilder(
          animation: _glowAnimation,
          builder: (context, child) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    widget.accentColor.withOpacity(
                      _isPressed ? 0.4 : (_isHovered ? 0.25 : 0.15),
                    ),
                    widget.accentColor.withOpacity(
                      _isPressed ? 0.2 : (_isHovered ? 0.12 : 0.08),
                    ),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: widget.isLoading
                      ? widget.accentColor.withOpacity(_glowAnimation.value)
                      : widget.accentColor.withOpacity(
                          _isPressed ? 0.8 : (_isHovered ? 0.6 : 0.4),
                        ),
                  width: widget.isLoading ? 2 : (_isPressed ? 2 : 1.5),
                ),
                boxShadow: widget.isLoading || _isHovered
                    ? [
                        BoxShadow(
                          color: widget.accentColor.withOpacity(
                            widget.isLoading
                                ? _glowAnimation.value * 0.5
                                : (_isHovered ? 0.3 : 0),
                          ),
                          blurRadius: widget.isLoading ? 25 : 20,
                          spreadRadius: widget.isLoading ? 0 : -2,
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Shimmer effect when loading
                    if (widget.isLoading)
                      Positioned.fill(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 1000),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                widget.accentColor.withOpacity(0.1),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                          ),
                        ),
                      ),

                    // Content
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.isLoading)
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(
                                widget.accentColor,
                              ),
                            ),
                          )
                        else
                          Icon(
                            widget.icon,
                            color: widget.isDisabled
                                ? AntaresColors.textDisabled
                                : widget.accentColor,
                            size: 22,
                          ),
                        const SizedBox(width: 12),
                        Text(
                          widget.isLoading ? 'PROCESSING...' : widget.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: widget.isDisabled
                                ? AntaresColors.textDisabled
                                : widget.accentColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// Compact action button for secondary actions
class CompactActionButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback? onPressed;
  final bool isActive;
  final Color accentColor;
  final double size;

  const CompactActionButton({
    super.key,
    required this.icon,
    this.label,
    this.onPressed,
    this.isActive = false,
    this.accentColor = AntaresColors.cyan,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: label != null ? null : size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isActive
            ? accentColor.withOpacity(0.15)
            : AntaresColors.surfaceVariant,
        border: Border.all(
          color: isActive
              ? accentColor.withOpacity(0.5)
              : AntaresColors.border.withOpacity(0.5),
          width: isActive ? 1.5 : 1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: accentColor.withOpacity(0.2),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isActive ? accentColor : AntaresColors.textSecondary,
                ),
                if (label != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    label!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isActive ? accentColor : AntaresColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
