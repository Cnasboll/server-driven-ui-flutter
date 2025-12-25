import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';
import 'package:shql/execution/runtime_error.dart';

class BreakStatementExecutionNode extends ExecutionNode {
  BreakStatementExecutionNode({required super.thread, required super.scope});
  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) async {
    var breakTarget = thread.currentBreakTarget;
    if (breakTarget == null) {
      error = RuntimeError('Break statement used outside of a loop.');
      return TickResult.completed;
    }
    breakTarget.breakExecution();
    return TickResult.completed;
  }
}
