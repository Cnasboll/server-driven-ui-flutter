import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';
import 'package:shql/execution/runtime/runtime.dart';

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
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) async {
    result = await unaryFunction.function(executionContext, this, argument);
    return TickResult.completed;
  }
}
