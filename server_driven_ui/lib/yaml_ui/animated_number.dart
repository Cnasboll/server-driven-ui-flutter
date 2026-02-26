import 'package:flutter/material.dart';

/// Animates a numeric value from its previous to its current state.
class AnimatedNumber extends StatelessWidget {
  final num value;
  final TextStyle? style;
  final Duration duration;

  const AnimatedNumber({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        return Text(
          animated.toInt().toString(),
          style: style,
        );
      },
    );
  }
}
