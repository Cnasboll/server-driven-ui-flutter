import 'package:server_driven_ui/shql/tokenizer/token.dart';

/// A span in source code, represented as a tuple of start and end locations.
/// Both locations use 1-based line and column numbers (human-readable).
typedef CodeSpan = (CodeLocation?, CodeLocation?);

/// Extension methods for CodeSpan
extension CodeSpanExtensions on CodeSpan {
  /// Extracts an excerpt from the source code showing the span with highlighting.
  ///
  /// For single-line spans, shows the line with tildes (~) under the span.
  /// For multi-line spans, shows all lines that were consumed up to the error,
  /// with tildes on the last line pointing to where the error was detected.
  ///
  /// Example output for single-line span:
  /// ```
  /// Line 42:
  /// FUNCTION foo() BEGIN
  /// ~~~~~~~~
  /// ```
  String excerpt(String sourceCode) {
    final (start, end) = this;
    if (start == null || end == null) {
      return '';
    }

    final lines = sourceCode.split('\n');

    // Handle single-line span - show just that line with underline
    if (start.lineNumber == end.lineNumber) {
      final lineIndex = start.lineNumber - 1; // Convert to 0-based
      if (lineIndex < 0 || lineIndex >= lines.length) return '';

      final line = lines[lineIndex];
      final startCol = start.columnNumber - 1; // Convert to 0-based
      final endCol = end.columnNumber - 1;

      // Build the underline with tildes
      final tildeCount = (endCol - startCol).clamp(
        1,
        (line.length - startCol).clamp(1, line.length),
      );
      final underline = ' ' * startCol + '~' * tildeCount;

      return '''
Line ${start.lineNumber}:
$line
$underline
''';
    }

    // Handle multi-line span - show all consumed lines plus underline on last line
    final result = StringBuffer();

    result.writeln('Lines ${start.lineNumber}-${end.lineNumber}:');

    // Show all lines from start to end (inclusive)
    for (
      int i = start.lineNumber - 1;
      i <= end.lineNumber - 1 && i < lines.length;
      i++
    ) {
      final lineNumber = i + 1;
      final lineContent = lines[i];

      // On the last line, only show content up to the end column
      if (lineNumber == end.lineNumber) {
        final endCol = end.columnNumber - 1; // Convert to 0-based
        final truncatedLine = lineContent.substring(
          0,
          endCol.clamp(0, lineContent.length),
        );
        result.writeln('$lineNumber: $truncatedLine');
      } else {
        result.writeln('$lineNumber: $lineContent');
      }
    }

    // Add underline on the error line to show where parsing stopped
    final endCol = end.columnNumber - 1;
    // Calculate padding to align with line numbers: "N: " where N is the line number
    final linePrefixLength = end.lineNumber.toString().length + 2;
    final underline = ' ' * linePrefixLength + '~' * endCol.clamp(1, 100);
    result.write(underline);

    return result.toString();
  }
}
