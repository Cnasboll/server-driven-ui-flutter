import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';
import 'package:shql/execution/runtime/runtime.dart';

class BinaryFunctionExecutionNode extends ExecutionNode {
  final BinaryFunction binaryFunction;
  final dynamic argument1;
  final dynamic argument2;

  BinaryFunctionExecutionNode(
    this.binaryFunction,
    this.argument1,
    this.argument2, {
    required super.thread,
    required super.scope,
  });

  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) async {
    result = await binaryFunction.function(
      executionContext,
      this,
      argument1,
      argument2,
    );
    return TickResult.completed;
  }
}
