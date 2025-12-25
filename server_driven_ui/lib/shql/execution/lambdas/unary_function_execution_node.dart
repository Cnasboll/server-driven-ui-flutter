import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime.dart';

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
    Runtime runtime,
    CancellationToken? cancellationToken,
  ) async {
    result = await unaryFunction.function(this, argument);
    return TickResult.completed;
  }
}
