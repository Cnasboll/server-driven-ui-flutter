import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/engine/engine.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/lazy_execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime/execution.dart';

class WhileLoopExecutionNode extends LazyExecutionNode {
  WhileLoopExecutionNode(
    super.node, {
    required super.thread,
    required super.scope,
  });

  ExecutionNode? _conditionNode;
  ExecutionNode? _bodyNode;

  @override
  Future<TickResult> doTick(
    Execution execution,
    CancellationToken? cancellationToken,
  ) async {
    if (_conditionNode == null) {
      _conditionNode = Engine.createExecutionNode(
        node.children[0],
        thread,
        scope,
      );
      return TickResult.delegated;
    }

    var conditionResult = _conditionNode!.result;
    if (!conditionResult) {
      _complete(execution);
      return TickResult.completed;
    }

    if (_bodyNode == null) {
      _bodyNode = Engine.createExecutionNode(node.children[1], thread, scope);
      return TickResult.delegated;
    }
    _propagateResult();
    return TickResult.iterated;
  }

  void _propagateResult() {
    if (_bodyNode != null) {
      if (_bodyNode!.completed) {
        result = _bodyNode!.result;
        error ??= _bodyNode!.error;
      }
      _bodyNode = null;
    } else if (_conditionNode != null) {
      if (_conditionNode!.completed) {
        result ??= _conditionNode!.result;
        error ??= _conditionNode!.error;
      }
    }
    _conditionNode = null;
    _bodyNode = null;
  }

  TickResult _complete(Execution execution) {
    _propagateResult();
    return TickResult.completed;
  }

  @override
  bool get isLoop => true;

  @override
  void continueLoop() {
    _propagateResult();
  }
}
