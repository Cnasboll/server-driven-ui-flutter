import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/execution/binary_execution_node.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';

abstract class BooleanExecutionNode extends BinaryExecutionNode {
  BooleanExecutionNode(
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

    result = apply();
    return TickResult.completed;
  }

  bool get lhsBoolResult => lhsResult is bool ? lhsResult : lhsResult != null && lhsResult != 0;
  bool get rhsBoolResult => rhsResult is bool ? rhsResult : rhsResult != null && rhsResult != 0;

  bool shortCircuit();
  bool apply();
}
