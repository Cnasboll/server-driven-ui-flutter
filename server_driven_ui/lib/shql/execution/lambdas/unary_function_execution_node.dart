import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime/execution.dart';
import 'package:server_driven_ui/shql/execution/runtime/runtime.dart';

class UnaryFunctionExecutionNode extends ExecutionNode {
  final UnaryFunction unaryFunction;
  final dynamic argument;

  UnaryFunctionExecutionNode(
    this.unaryFunction,
    this.argument, {
    required super.thread,
    required super.scope,
  });

  @override
  Future<TickResult> doTick(
    Execution execution,
    CancellationToken? cancellationToken,
  ) async {
    result = await unaryFunction.function(execution, this, argument);
    return TickResult.completed;
  }
}
