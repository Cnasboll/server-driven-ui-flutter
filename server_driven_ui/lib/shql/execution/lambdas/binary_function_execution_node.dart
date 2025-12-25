import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime.dart';

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
    Runtime runtime,
    CancellationToken? cancellationToken,
  ) async {
    result = await binaryFunction.function(this, argument1, argument2);
    return TickResult.completed;
  }
}
