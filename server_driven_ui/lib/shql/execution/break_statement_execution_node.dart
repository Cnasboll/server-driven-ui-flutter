import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime.dart';

class BreakStatementExecutionNode extends ExecutionNode {
  BreakStatementExecutionNode({required super.thread, required super.scope});
  @override
  Future<TickResult> doTick(
    Runtime runtime,
    CancellationToken? cancellationToken,
  ) async {
    var breakTarget = thread.currentBreakTarget;
    if (breakTarget == null) {
      error = 'Break statement used outside of a loop.';
      return TickResult.completed;
    }
    breakTarget.breakExecution();
    return TickResult.completed;
  }
}
