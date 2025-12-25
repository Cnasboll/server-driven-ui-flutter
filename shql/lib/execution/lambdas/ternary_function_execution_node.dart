import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';
import 'package:shql/execution/runtime/runtime.dart';

class TernaryFunctionExecutionNode extends ExecutionNode {
  final TernaryFunction ternaryFunction;
  final dynamic argument1;
  final dynamic argument2;
  final dynamic argument3;

  TernaryFunctionExecutionNode(
    this.ternaryFunction,
    this.argument1,
    this.argument2,
    this.argument3, {
    required super.thread,
    required super.scope,
  });

  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) async {
    result = await ternaryFunction.function(
      executionContext,
      this,
      argument1,
      argument2,
      argument3,
    );
    return TickResult.completed;
  }
}
