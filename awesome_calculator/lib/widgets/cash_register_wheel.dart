import 'package:flutter/material.dart';

/// A single cash register wheel that can display numbers, letters, and symbols.
///
/// Features:
/// - Smooth rotation animation between characters
/// - Bronze/brass metallic appearance
/// - Embossed characters with depth
/// - Full ASCII character set support
class CashRegisterWheel extends StatefulWidget {
  final String character;
  final Duration animationDuration;

  const CashRegisterWheel({
    super.key,
    required this.character,
    this.animationDuration = const Duration(milliseconds: 400),
  });

  @override
  State<CashRegisterWheel> createState() => _CashRegisterWheelState();
}

class _CashRegisterWheelState extends State<CashRegisterWheel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  String _currentChar = ' ';
  String _targetChar = ' ';

  // Character set on the wheel (visible characters)
  static const String _wheelChars =
      ' 0123456789'
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
      'abcdefghijklmnopqrstuvwxyz'
      '+-*/=<>!?.,;:\'"()[]{}@#\$%&_|\\';

  @override
  void initState() {
    super.initState();
    _currentChar = widget.character;
    _targetChar = widget.character;
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _animation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(CashRegisterWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only trigger a rotation when the character actually changed
    // Compare against the previous widget configuration to avoid
    // reacting to frequent parent rebuilds (e.g. blinking cursor) which
    // call didUpdateWidget even when the character is unchanged.
    if (widget.character != oldWidget.character) {
      _currentChar = _targetChar;
      _targetChar = widget.character;
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _getCharIndex(String char) {
    final index = _wheelChars.indexOf(char);
    return index == -1 ? 0 : index; // Default to space if not found
  }

  double _getRotationOffset() {
    final currentIndex = _getCharIndex(_currentChar);
    final targetIndex = _getCharIndex(_targetChar);
    final totalChars = _wheelChars.length;

    // Calculate shortest rotation direction
    var diff = targetIndex - currentIndex;
    if (diff.abs() > totalChars / 2) {
      diff = diff > 0 ? diff - totalChars : diff + totalChars;
    }

    return currentIndex + (diff * _animation.value);
  }

  @override
  Widget build(BuildContext context) {
    const wheelHeight = 50.0;
    const charHeight = 16.0;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final rotationOffset = _getRotationOffset();

        return Container(
          width: 28,
          height: wheelHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFF8B4513), // Saddle brown
                Color(0xFFCD7F32), // Bronze
                Color(0xFFDAA520), // Goldenrod
                Color(0xFFCD7F32), // Bronze
                Color(0xFF8B4513), // Saddle brown
              ],
            ),
            boxShadow: [
              const BoxShadow(
                color: Colors.black54,
                blurRadius: 8,
                offset: Offset(2, 2),
              ),
              BoxShadow(
                color: const Color(0xFFDAA520).withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(-1, -1),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                // Wheel characters
                Positioned.fill(
                  child: ClipRect(
                    child: OverflowBox(
                      // Use a tripled char column so we can smoothly wrap-around
                      maxHeight: _wheelChars.length * 3 * charHeight,
                      child: Builder(
                        builder: (context) {
                          // Compute integer base and fractional part for smooth animation
                          final totalChars = _wheelChars.length;
                          final baseIndex = rotationOffset.floor();
                          final frac = rotationOffset - baseIndex;

                          int centerIndex = baseIndex % totalChars;
                          if (centerIndex < 0) centerIndex += totalChars;
                          final prevIndex = (centerIndex - 1) % totalChars;
                          final nextIndex = (centerIndex + 1) % totalChars;
                          final chars = _wheelChars.split('');

                          return Center(
                            child: Transform.translate(
                              offset: Offset(0, -frac * charHeight),
                              child: SizedBox(
                                height: charHeight * 3,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      height: charHeight,
                                      child: Center(
                                        child: Text(
                                          chars[prevIndex],
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'monospace',
                                            color: Color(
                                              0xFFFFE4B5,
                                            ).withValues(alpha: 0.71),
                                            shadows: [
                                              // faint top-left highlight for subtle emboss
                                              Shadow(
                                                color: Colors.white.withValues(
                                                  alpha: 0.55,
                                                ),
                                                offset: Offset(-0.6, -0.6),
                                                blurRadius: 0.0,
                                              ),
                                              // warm mid glow
                                              Shadow(
                                                color: const Color(
                                                  0xFFDAA520,
                                                ).withValues(alpha: 0.20),
                                                offset: Offset(0, 0.6),
                                                blurRadius: 2.5,
                                              ),
                                              // small contour shadow (bottom-right)
                                              Shadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.28,
                                                ),
                                                offset: Offset(0.6, 0.9),
                                                blurRadius: 1.2,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: charHeight,
                                      child: Center(
                                        child: Text(
                                          chars[centerIndex],
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w900,
                                            fontFamily: 'monospace',
                                            color: Color(0xFFFFF8E1),
                                            letterSpacing: 0.3,
                                            shadows: [
                                              // light highlight (top-left)
                                              Shadow(
                                                color: Colors.white.withValues(
                                                  alpha: 0.85,
                                                ),
                                                offset: Offset(-1, -1),
                                                blurRadius: 0,
                                              ),
                                              // warm glow / bloom
                                              Shadow(
                                                color: const Color(
                                                  0xFFDAA520,
                                                ).withValues(alpha: 0.44),
                                                offset: Offset(0, 1),
                                                blurRadius: 6,
                                              ),
                                              // darker contour shadow (bottom-right)
                                              Shadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.50,
                                                ),
                                                offset: Offset(1, 2),
                                                blurRadius: 2,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: charHeight,
                                      child: Center(
                                        child: Text(
                                          chars[nextIndex],
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'monospace',
                                            color: Color(
                                              0xFFFFE4B5,
                                            ).withValues(alpha: 0.71),
                                            shadows: [
                                              // faint top-left highlight for subtle emboss
                                              Shadow(
                                                color: Colors.white.withValues(
                                                  alpha: 0.55,
                                                ),
                                                offset: Offset(-0.6, -0.6),
                                                blurRadius: 0.0,
                                              ),
                                              // warm mid glow
                                              Shadow(
                                                color: const Color(
                                                  0xFFDAA520,
                                                ).withValues(alpha: 0.20),
                                                offset: Offset(0, 0.6),
                                                blurRadius: 2.5,
                                              ),
                                              // small contour shadow (bottom-right)
                                              Shadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.28,
                                                ),
                                                offset: Offset(0.6, 0.9),
                                                blurRadius: 1.2,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                // Viewport window (strong vignette to hide adjacent chars)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.95),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.95),
                        ],
                        stops: const [0.0, 0.35, 0.65, 1.0],
                      ),
                    ),
                  ),
                ),
                // Center character highlight (golden gradient)
                Positioned(
                  left: 0,
                  right: 0,
                  top: (wheelHeight / 2) - (charHeight / 2),
                  height: charHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFDAA520).withValues(alpha: 0.08),
                          Color(0xFFDAA520).withValues(alpha: 0.14),
                          Color(0xFFDAA520).withValues(alpha: 0.08),
                        ],
                      ),
                    ),
                  ),
                ),
                // Glass reflection (dimmer)
                Positioned(
                  top: 8,
                  left: 4,
                  right: 20,
                  height: 20,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.12),
                          Colors.white.withValues(alpha: 0.03),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
