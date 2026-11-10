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
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool hoverable;
  final bool highlight;
  final Gradient? gradient;

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
            : AppColors.border;

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: widget.padding,
      decoration: BoxDecoration(
        gradient: widget.gradient ??
            const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF151D29), Color(0xFF10161F)],
            ),
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
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
