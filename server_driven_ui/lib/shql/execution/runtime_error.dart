import 'package:server_driven_ui/shql/parser/parse_tree.dart';
import 'package:server_driven_ui/shql/tokenizer/code_span.dart';

/// Represents a runtime error with an error message and optional source code context.
class RuntimeError {
  final String message;
  final String? sourceCode;
  final CodeSpan? codeSpan;

  RuntimeError(this.message, {this.sourceCode, this.codeSpan});

  /// Creates a RuntimeError from a ParseTree, extracting token span and source code for context
  RuntimeError.fromParseTree(this.message, ParseTree parseTree)
    : sourceCode = parseTree.sourceCode,
      codeSpan = parseTree.tokenSpan;

  /// Formats the error message with source code context if available
  String get formattedMessage {
    if (sourceCode == null || codeSpan == null) {
      return message;
    }

    final excerpt = codeSpan!.excerpt(sourceCode!);
    if (excerpt.isEmpty) {
      return message;
    }

    return '$message\n$excerpt';
  }

  @override
  String toString() => formattedMessage;
}
