import 'package:awesome_calculator/widgets/lightbulb.dart';
import 'package:awesome_calculator/widgets/rivet.dart';
import 'package:flutter/material.dart';

/// A steampunk-styled mechanical key button with animated drum rotation.
///
/// Features:
/// - Bronze/copper gradient with rivets and lightbulb indicators
/// - Rotating drum animation showing both shifted and unshifted characters
/// - 1.8 second smooth rotation when shift state changes
/// - Special handling for wide keys (SPACE, ENTER, TAB, etc.)
class KeyButton extends StatefulWidget {
  final String label;
  final String? baseKey;
  final bool isPressed;
  final VoidCallback onPressed;
  final bool isShifted;
  final Map<String, String> shiftMap;
  final bool isExecuting;

  const KeyButton({
    super.key,
    required this.label,
    this.baseKey,
    required this.isPressed,
    required this.onPressed,
    required this.isShifted,
    required this.shiftMap,
    this.isExecuting = false,
  });

  @override
  State<KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<KeyButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;
  late Animation<double> _rotationAnimation;
  bool _lastShiftState = false;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
      value: 0.0,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.easeInOut),
    );
    _lastShiftState = false;

    // Set initial state after first frame if shift is already pressed
    if (widget.isShifted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rotationController.value = 1.0;
        _lastShiftState = true;
      });
    }
  }

  @override
  void didUpdateWidget(KeyButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isShifted != _lastShiftState) {
      if (widget.isShifted) {
        _rotationController.forward();
      } else {
        _rotationController.reverse();
      }
      _lastShiftState = widget.isShifted;
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Always use widget.baseKey which contains the original unshifted key
    final baseKey = widget.baseKey!;
    final isBreakKey = baseKey == 'BREAK';
    final isFunctionKey =
        baseKey == 'SIN' ||
        baseKey == 'COS' ||
        baseKey == 'TAN' ||
        baseKey == 'ASIN' ||
        baseKey == 'ACOS' ||
        baseKey == 'ATAN' ||
        baseKey == 'SQRT' ||
        baseKey == 'EXP' ||
        baseKey == 'LOG';
    final isWide =
        baseKey == 'SPACE' ||
        baseKey == 'BACK' ||
        baseKey == 'DEL' ||
        baseKey == 'SHIFT' ||
        baseKey == 'TAB' ||
        baseKey == 'LOAD' ||
        baseKey == 'RESET' ||
        isBreakKey;
    final isEnter = baseKey == 'ENTER';
    final width = isFunctionKey
        ? 45.0
        : (isWide ? 60.0 : (isEnter ? 50.0 : 24.0));

    final unshifted = baseKey;
    final shifted = widget.shiftMap[baseKey] ?? baseKey;
    final showBoth = unshifted != shifted;

    final bool isBreakAndNotExecuting = isBreakKey && !widget.isExecuting;

    final buttonContent = AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      width: width,
      height: 32,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isBreakKey && widget.isExecuting
              ? [
                  const Color(0xFFD32F2F), // Red
                  const Color(0xFFB71C1C), // Darker Red
                  const Color(0xFF880E4F), // Darkest Red
                ]
              : [
                  const Color(0xFFCD7F32), // Bronze
                  const Color(0xFFB87333), // Copper
                  const Color(0xFF8B4513), // Saddle brown
                ],
        ),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: const Color(0xFF4A3728), // Dark brown
          width: 2,
        ),
        boxShadow: [
          const BoxShadow(
            color: Colors.black87,
            offset: Offset(3, 3),
            blurRadius: 4,
          ),
          BoxShadow(
            color: const Color(0xFFCD7F32).withAlpha(77),
            offset: const Offset(-1, -1),
            blurRadius: 2,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Lightbulb at top center
          Positioned(
            top: 2,
            left: width / 2 - 4,
            child: Lightbulb(isLit: widget.isPressed),
          ),
          // Rivets in corners
          Positioned(top: 2, left: 2, child: Rivet()),
          Positioned(top: 2, right: 2, child: Rivet()),
          Positioned(bottom: 2, left: 2, child: Rivet()),
          Positioned(bottom: 2, right: 2, child: Rivet()),
          // Text with drum rotation effect
          Positioned(
            left: 0,
            right: 0,
            top: 14,
            bottom: -2,
            child: showBoth
                ? AnimatedBuilder(
                    animation: _rotationAnimation,
                    builder: (context, child) {
                      return OverflowBox(
                        maxHeight: 36,
                        child: Transform.translate(
                          offset: Offset(
                            0,
                            -18 + _rotationAnimation.value * 18,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Shifted character (moves into view when shift pressed)
                              SizedBox(
                                height: 18,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Text(
                                    shifted,
                                    style: const TextStyle(
                                      color: Color(0xFFFFE4B5),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                      height: 1.0,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black54,
                                          offset: Offset(1, 1),
                                          blurRadius: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              // Unshifted character (visible by default)
                              SizedBox(
                                height: 18,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Text(
                                    unshifted,
                                    style: const TextStyle(
                                      color: Color(0xFFFFE4B5),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                      height: 1.0,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black54,
                                          offset: Offset(1, 1),
                                          blurRadius: 2,
                                        ),
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
                  )
                : Center(
                    child: Text(
                      widget.isShifted && shifted != unshifted
                          ? shifted
                          : baseKey,
                      style: TextStyle(
                        color: const Color(0xFFFFE4B5),
                        fontSize: isWide ? 8 : 11,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        shadows: const [
                          Shadow(
                            color: Colors.black54,
                            offset: Offset(1, 1),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: isBreakAndNotExecuting ? null : widget.onPressed,
      child: isBreakAndNotExecuting
          ? Opacity(opacity: 0.5, child: buttonContent)
          : buttonContent,
    );
  }
}
