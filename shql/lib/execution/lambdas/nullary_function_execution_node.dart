import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';
import 'package:shql/execution/runtime/runtime.dart';

class NullaryFunctionExecutionNode extends ExecutionNode {
  final NullaryFunction nullaryFunction;

  NullaryFunctionExecutionNode(
    this.nullaryFunction, {
    required super.thread,
    required super.scope,
  });

  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) async {
    result = await nullaryFunction.function(executionContext, this);
    return TickResult.completed;
  }
}
