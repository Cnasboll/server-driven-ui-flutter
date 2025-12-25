import 'package:flutter/material.dart';

class Lightbulb extends StatelessWidget {
  const Lightbulb({super.key, required this.isLit});

  final bool isLit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isLit
            ? const Color(0xFFFFF8DC) // Bright cornsilk when lit
            : const Color(0xFF4A3728), // Dark when off
        border: Border.all(color: const Color(0xFF2C1810), width: 1),
        boxShadow: isLit
            ? [
                BoxShadow(
                  color: const Color(0xFFFFFF99).withValues(alpha: 0.9),
                  blurRadius: 12,
                  spreadRadius: 3,
                ),
                BoxShadow(
                  color: const Color(0xFFFFDD55).withValues(alpha: 0.6),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 1,
                ),
              ],
      ),
      child: isLit
          ? Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFFFFF),
                    const Color(0xFFFFF8DC),
                    const Color(0xFFFFD700),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
