import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/engine/engine.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/lazy_execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime/execution_context.dart';

abstract class UnaryExecutionNode extends LazyExecutionNode {
  UnaryExecutionNode(super.node, {required super.thread, required super.scope});

  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) async {
    if (operand == null) {
      operand = Engine.createExecutionNode(node, thread, scope);
      return TickResult.delegated;
    }

    result = await apply();
    return TickResult.completed;
  }

  ExecutionNode? operand;
  dynamic get operandResult => operand!.result;
  Future<dynamic> apply();
}
