import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/engine/engine.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/lazy_execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime.dart';

class ProgramExecutionNode extends LazyExecutionNode {
  ProgramExecutionNode(
    super.node, {
    required super.thread,
    required super.scope,
  });

  @override
  Future<TickResult> doTick(
    Runtime runtime,
    CancellationToken? cancellationToken,
  ) async {
    if (_currentStatement != null) {
      result = _currentStatement!.result;
      error ??= _currentStatement!.error;
    }
    if (_statementIndex < node.children.length) {
      _currentStatement = Engine.createExecutionNode(
        node.children[_statementIndex++],
        thread,
        scope,
      );
      if (_currentStatement == null) {
        error = 'Failed to create execution node for statement.';
        return TickResult.completed;
      }
      return TickResult.delegated;
    }
    return TickResult.completed;
  }

  int _statementIndex = 0;
  ExecutionNode? _currentStatement;
}
