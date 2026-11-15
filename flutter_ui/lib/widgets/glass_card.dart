import 'package:flutter/material.dart';

import '../theme.dart';

class GlassCard extends StatefulWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 22,
    this.hoverable = false,
    this.highlight = false,
    this.gradient,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool hoverable;
  final bool highlight;
  final Gradient? gradient;
  final Color? borderColor;

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.highlight
        ? AppColors.accent.withValues(alpha: 0.55)
        : _hover && widget.hoverable
            ? AppColors.accent.withValues(alpha: 0.30)
            : widget.borderColor ?? AppColors.border;

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: widget.padding,
      decoration: BoxDecoration(
        gradient: widget.gradient ?? AppColors.tileGradient,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: borderColor),
      ),
      child: widget.child,
    );

    if (!widget.hoverable) return content;

    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: content,
    );
  }
}
