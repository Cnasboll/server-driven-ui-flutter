import 'package:flutter/material.dart';
import 'key_button.dart';

class Keyboard extends StatelessWidget {
  final List<List<String>> keyboardLayout;
  final Map<String, String> shiftMap;
  final String? pressedKey;
  final bool isShifted;
  final bool virtualShiftToggled;
  final bool physicalShiftPressed;
  final void Function(String) onKeyPress;
  final bool isExecuting;

  const Keyboard({
    super.key,
    required this.keyboardLayout,
    required this.shiftMap,
    required this.pressedKey,
    required this.isShifted,
    required this.virtualShiftToggled,
    required this.physicalShiftPressed,
    required this.onKeyPress,
    this.isExecuting = false,
  });

  String _getDisplayLabel(String key) {
    if (!isShifted) return key;

    // If shift is pressed, show shifted character
    if (shiftMap.containsKey(key)) {
      return shiftMap[key]!;
    }
    return key;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: keyboardLayout.map((row) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: row.map((key) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: KeyButton(
                      label: _getDisplayLabel(key),
                      baseKey: key,
                      isPressed:
                          pressedKey == key ||
                          (key == 'SHIFT' &&
                              (virtualShiftToggled || physicalShiftPressed)),
                      onPressed: () => onKeyPress(key),
                      isShifted: isShifted,
                      shiftMap: shiftMap,
                      isExecuting: isExecuting,
                    ),
                  );
                }).toList(),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
