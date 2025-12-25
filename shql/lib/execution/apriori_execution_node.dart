import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';

class AprioriExecutionNode extends ExecutionNode {
  AprioriExecutionNode(
    dynamic result, {
    required super.thread,
    required super.scope,
  }) {
    this.result = result;
    completed = true;
  }

  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) async {
    return TickResult.completed;
  }
}
