import 'package:flutter/material.dart';

import '../theme.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.ok,
    required this.hasError,
    this.label,
  });

  final bool ok;
  final bool hasError;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = hasError
        ? AppColors.red
        : ok
            ? AppColors.green
            : AppColors.amber;
    final text = label ??
        (hasError
            ? 'SMC unavailable'
            : ok
                ? 'SMC connected'
                : 'Connecting…');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 7,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
