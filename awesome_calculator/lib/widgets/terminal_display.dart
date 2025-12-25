import 'package:awesome_calculator/widgets/glare.dart';
import 'package:awesome_calculator/widgets/graph_display.dart';
import 'package:awesome_calculator/widgets/screen_crack.dart';
import 'package:flutter/material.dart';

class TerminalDisplay extends StatelessWidget {
  final String terminalText;
  final int cursorPosition;
  final bool showCursor;
  final int inputStartPosition;
  final String promptSymbol;
  final VoidCallback onTapRequest;
  final void Function(int position) onCursorPositionChanged;
  final List<Offset> plotPoints;

  const TerminalDisplay({
    super.key,
    required this.terminalText,
    required this.cursorPosition,
    required this.showCursor,
    required this.inputStartPosition,
    required this.promptSymbol,
    required this.onTapRequest,
    required this.onCursorPositionChanged,
    required this.plotPoints,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: GestureDetector(
          onTapDown: (details) {
            onTapRequest();
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(48),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF001100),
                borderRadius: BorderRadius.circular(48),
                border: Border.all(color: const Color(0xFF00FF00), width: 4),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00FF00).withValues(alpha: 0.6),
                    blurRadius: 40,
                    spreadRadius: 6,
                  ),
                  const BoxShadow(
                    color: Colors.black87,
                    blurRadius: 15,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // CRT glare effect - white spot in upper right
                  Positioned(top: -20, right: -20, child: const Glare()),
                  // Screen crack in lower left corner
                  Positioned(bottom: 15, left: 15, child: const ScreenCrack()),
                  // Terminal content
                  SingleChildScrollView(
                    reverse: true,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return GestureDetector(
                          onTapDown: (details) {
                            // Calculate approximate cursor position
                            final textPainter = TextPainter(
                              text: TextSpan(
                                text: terminalText,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 20,
                                  color: Color(0xFF00FF00),
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              textDirection: TextDirection.ltr,
                              maxLines: null,
                            )..layout(maxWidth: constraints.maxWidth);

                            final position = textPainter.getPositionForOffset(
                              details.localPosition,
                            );

                            final clickedPosition = position.offset.clamp(
                              0,
                              terminalText.length,
                            );

                            // Only allow clicking within current input section (after current prompt)
                            final newPosition = clickedPosition.clamp(
                              inputStartPosition,
                              terminalText.length,
                            );

                            onCursorPositionChanged(newPosition);
                            onTapRequest();
                          },
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 20,
                                color: Color(0xFF00FF00),
                                fontWeight: FontWeight.w500,
                                letterSpacing: 1.2,
                              ),
                              children: [
                                TextSpan(
                                  text: terminalText.substring(
                                    0,
                                    cursorPosition,
                                  ),
                                ),
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.baseline,
                                  baseline: TextBaseline.alphabetic,
                                  child: Container(
                                    width: 12,
                                    height: 24,
                                    color: showCursor
                                        ? const Color(0xFF00FF00)
                                        : Colors.transparent,
                                  ),
                                ),
                                TextSpan(
                                  text: terminalText.substring(cursorPosition),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (plotPoints.isNotEmpty)
                    Positioned.fill(child: GraphDisplay(points: plotPoints)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
