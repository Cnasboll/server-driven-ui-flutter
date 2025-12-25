import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/engine/engine.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/lazy_execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';

class RepeatUntilLoopExecutionNode extends LazyExecutionNode {
  RepeatUntilLoopExecutionNode(
    super.node, {
    required super.thread,
    required super.scope,
  });

  ExecutionNode? _bodyNode;
  ExecutionNode? _conditionNode;

  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) async {
    if (_bodyNode == null) {
      _bodyNode = Engine.createExecutionNode(node.children[0], thread, scope);
      return TickResult.delegated;
    }

    if (_conditionNode == null) {
      if (_bodyNode!.completed) {
        result = _bodyNode!.result;
        error ??= _bodyNode!.error;
      }
      _conditionNode = Engine.createExecutionNode(
        node.children[1],
        thread,
        scope,
      );
      return TickResult.delegated;
    }

    var conditionResult = _conditionNode!.result;
    if (conditionResult) {
      _complete(executionContext);
      return TickResult.completed;
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

  TickResult _complete(ExecutionContext executionContext) {
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
