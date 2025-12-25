import 'package:flutter/material.dart';

class Rivet extends StatelessWidget {
  const Rivet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(
        color: const Color(0xFF4A3728),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 1),
        ],
      ),
    );
  }
}
