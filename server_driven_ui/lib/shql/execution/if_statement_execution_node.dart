import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/engine/engine.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/lazy_execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime.dart';

class IfStatementExecutionNode extends LazyExecutionNode {
  IfStatementExecutionNode(
    super.node, {
    required super.thread,
    required super.scope,
  });

  ExecutionNode? _conditionNode;
  ExecutionNode? _branchNode;

  @override
  Future<TickResult> doTick(
    Runtime runtime,
    CancellationToken? cancellationToken,
  ) async {
    if (_conditionNode == null) {
      _conditionNode ??= Engine.createExecutionNode(
        node.children[0],
        thread,
        scope,
      );
      return TickResult.delegated;
    }

    if (_branchNode == null) {
      var conditionResult = _conditionNode!.result;
      if (conditionResult == true) {
        _branchNode = Engine.createExecutionNode(
          node.children[1],
          thread,
          scope,
        );
        return TickResult.delegated;
      }

      if (node.children.length <= 2) {
        // No else branch
        result = false;
        return TickResult.completed;
      }

      // Else branch
      _branchNode = Engine.createExecutionNode(node.children[2], thread, scope);
      return TickResult.delegated;
    }

    result = _branchNode!.result;
    error = _branchNode!.error;
    return TickResult.completed;
  }
}
