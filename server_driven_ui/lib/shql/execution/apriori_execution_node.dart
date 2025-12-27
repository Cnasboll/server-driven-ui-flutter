import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime/execution_context.dart';

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
