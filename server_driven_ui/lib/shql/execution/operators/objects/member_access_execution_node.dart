import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/identifier_exeuction_node.dart';
import 'package:server_driven_ui/shql/execution/lazy_execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime/execution_context.dart';
import 'package:server_driven_ui/shql/execution/runtime/runtime.dart';
import 'package:server_driven_ui/shql/execution/runtime_error.dart';
import 'package:server_driven_ui/shql/tokenizer/token.dart';

class MemberAccessExecutionNode extends LazyExecutionNode {
  MemberAccessExecutionNode(
    super.node, {
    required super.thread,
    required super.scope,
  });

  IdentifierExecutionNode? _leftIdentifierNode;
  IdentifierExecutionNode? _rightIdentifierNode;

  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) async {
    if (node.children.length != 2) {
      error = RuntimeError.fromParseTree(
        'Member access must have exactly 2 children',
        node,
        sourceCode: executionContext.sourceCode,
      );
      return TickResult.completed;
    }

    if (_leftIdentifierNode == null) {
      if (node.children[0].symbol != Symbols.identifier) {
        error = RuntimeError.fromParseTree(
          'Left side of member access must be an identifier',
          node.children[0],
          sourceCode: executionContext.sourceCode,
        );
        return TickResult.completed;
      }
      _leftIdentifierNode = IdentifierExecutionNode(
        node.children[0],
        thread: thread,
        scope: scope,
      );
      return TickResult.delegated;
    }

    var leftIdentifierResult = _leftIdentifierNode!.result;
    if (leftIdentifierResult is! Scope) {
      error = RuntimeError.fromParseTree(
        'Left side of member access did not resolve to an scope',
        node.children[0],
        sourceCode: executionContext.sourceCode,
      );
      return TickResult.completed;
    }

    if (_rightIdentifierNode == null) {
      if (node.children[1].symbol != Symbols.identifier) {
        error = RuntimeError.fromParseTree(
          'Right side of member access must be an identifier',
          node.children[1],
          sourceCode: executionContext.sourceCode,
        );
        return TickResult.completed;
      }

      _rightIdentifierNode = IdentifierExecutionNode(
        node.children[1],
        thread: thread,
        scope: leftIdentifierResult,
      );
      return TickResult.delegated;
    }

    result = _rightIdentifierNode!.result;
    error ??= _rightIdentifierNode!.error;
    return TickResult.completed;
  }
}
