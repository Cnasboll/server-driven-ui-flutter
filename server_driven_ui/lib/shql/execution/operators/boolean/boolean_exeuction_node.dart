import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/execution/binary_execution_node.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime.dart';

abstract class BooleanExecutionNode extends BinaryExecutionNode {
  BooleanExecutionNode(
    super.lhsTree,
    super.rhsTree, {
    required super.thread,
    required super.scope,
  });

  @override
  Future<TickResult> doTick(
    Runtime runtime,
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

  bool get lhsBoolResult => lhsResult is bool ? lhsResult : lhsResult != 0;
  bool get rhsBoolResult => rhsResult is bool ? rhsResult : rhsResult != 0;

  bool shortCircuit();
  bool apply();
}
