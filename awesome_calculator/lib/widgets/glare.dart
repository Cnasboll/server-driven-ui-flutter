import 'package:flutter/material.dart';

class Glare extends StatelessWidget {
  const Glare({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0.25),
            Colors.transparent,
          ],
          stops: const [0.0, 0.12, 1.0],
        ),
      ),
    );
  }
}
