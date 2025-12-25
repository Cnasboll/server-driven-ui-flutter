import 'package:flutter/material.dart';

class ScreenCrack extends StatelessWidget {
  const ScreenCrack({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(60, 60), painter: _CrackPainter());
  }
}

/// Custom painter for a screen crack effect
class _CrackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final path = Path();

    // Start from bottom-left corner
    path.moveTo(0, size.height);

    // Main crack line with jagged edges
    path.lineTo(8, size.height - 10);
    path.lineTo(12, size.height - 8);
    path.lineTo(20, size.height - 18);
    path.lineTo(25, size.height - 20);
    path.lineTo(35, size.height - 32);
    path.lineTo(40, size.height - 35);
    path.lineTo(48, size.height - 45);

    // Branch crack 1
    final branch1 = Path();
    branch1.moveTo(20, size.height - 18);
    branch1.lineTo(15, size.height - 25);
    branch1.lineTo(18, size.height - 30);

    // Branch crack 2
    final branch2 = Path();
    branch2.moveTo(35, size.height - 32);
    branch2.lineTo(42, size.height - 38);
    branch2.lineTo(45, size.height - 42);

    // Branch crack 3
    final branch3 = Path();
    branch3.moveTo(40, size.height - 35);
    branch3.lineTo(42, size.height - 30);
    branch3.lineTo(44, size.height - 25);

    canvas.drawPath(path, paint);
    canvas.drawPath(branch1, paint);
    canvas.drawPath(branch2, paint);
    canvas.drawPath(branch3, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
