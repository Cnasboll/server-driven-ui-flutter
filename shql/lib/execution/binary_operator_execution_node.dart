import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/execution/binary_execution_node.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';
import 'package:shql/execution/runtime_error.dart';

abstract class BinaryOperatorExecutionNode extends BinaryExecutionNode {
  BinaryOperatorExecutionNode(
    super.lhsTree,
    super.rhsTree, {
    required super.thread,
    required super.scope,
  });

  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) async {
    if (lhs == null) {
      pushLhs();
      return TickResult.delegated;
    }

    if (shortCircuit()) {
      return TickResult.completed;
    }

    if (rhs == null) {
      pushRhs();
      return TickResult.delegated;
    }

    try {
      result = apply();
    } on TypeError catch (e) {
      error = RuntimeError(
        'Type error in operator: ${lhsResult?.runtimeType} and ${rhsResult?.runtimeType}: $e',
      );
    }
    return TickResult.completed;
  }

  dynamic apply();
  bool shortCircuit() => false;
}
