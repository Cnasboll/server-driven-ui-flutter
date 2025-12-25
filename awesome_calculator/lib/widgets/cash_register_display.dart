import 'package:flutter/material.dart';
import 'cash_register_wheel.dart';

/// Cash register display showing a result as rotating wheels.
///
/// Features:
/// - Displays strings, numbers, booleans across multiple wheels
/// - Auto-pads with spaces for alignment
/// - Steampunk bronze housing
class CashRegisterDisplay extends StatelessWidget {
  final String value;
  final int maxWheels;

  const CashRegisterDisplay({
    super.key,
    required this.value,
    this.maxWheels = 12,
  });

  @override
  Widget build(BuildContext context) {
    // Pad or truncate value to fit wheels
    final displayValue = value.length > maxWheels
        ? value.substring(0, maxWheels)
        : value.padRight(maxWheels, ' ');

    // displayValue prepared for wheels

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF4A3728), // Dark brown
            Color(0xFF6B4423), // Medium brown
            Color(0xFF4A3728), // Dark brown
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2C1810), width: 2),
        boxShadow: [
          const BoxShadow(
            color: Colors.black87,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0xFFCD7F32).withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < displayValue.length; i++) ...[
              CashRegisterWheel(
                character: displayValue[i],
                key: ValueKey('wheel_$i'),
              ),
              if (i < displayValue.length - 1) const SizedBox(width: 1),
            ],
          ],
        ),
      ),
    );
  }
}
