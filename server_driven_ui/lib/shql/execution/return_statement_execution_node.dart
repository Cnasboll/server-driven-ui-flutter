import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/engine/engine.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/lazy_execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime/execution_context.dart';
import 'package:server_driven_ui/shql/execution/runtime_error.dart';

class ReturnStatementExecutionNode extends LazyExecutionNode {
  ReturnStatementExecutionNode(
    super.node, {
    required super.thread,
    required super.scope,
  });

  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) async {
    var returnTarget = thread.currentReturnTarget;
    if (returnTarget == null) {
      error = RuntimeError.fromParseTree(
        'Return statement used outside of a function.',
        node,
        sourceCode: executionContext.sourceCode,
      );
      return TickResult.completed;
    }
    if (node.children.isNotEmpty && _returnValueNode == null) {
      if (node.children.length > 1) {
        error = RuntimeError.fromParseTree(
          'Return statement can have at most one child.',
          node,
          sourceCode: executionContext.sourceCode,
        );
        return TickResult.completed;
      }

      _returnValueNode = Engine.createExecutionNode(
        node.children[0],
        thread,
        scope,
      );
      if (_returnValueNode == null) {
        error = RuntimeError.fromParseTree(
          'Failed to create execution node for return value.',
          node.children[0],
          sourceCode: executionContext.sourceCode,
        );
        return TickResult.completed;
      }
      return TickResult.delegated;
    }

    if (_returnValueNode != null) {
      result = _returnValueNode!.result;
      error ??= _returnValueNode!.error;
      returnTarget.returnAValue(_returnValueNode!.result);
    } else {
      returnTarget.returnNothing();
    }
    return TickResult.completed;
  }

  ExecutionNode? _returnValueNode;
}
