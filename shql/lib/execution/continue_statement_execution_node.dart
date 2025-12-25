import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';
import 'package:shql/execution/runtime_error.dart';

class ContinueStatementExecutionNode extends ExecutionNode {
  ContinueStatementExecutionNode({required super.thread, required super.scope});
  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) async {
    var breakTarget = thread.currentBreakTarget;
    if (breakTarget == null) {
      error = RuntimeError('Continue statement used outside of a loop.');
      return TickResult.completed;
    }
    breakTarget.continueExecution();
    return TickResult.completed;
  }
}
