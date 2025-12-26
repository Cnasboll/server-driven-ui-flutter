import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/execution/binary_execution_node.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime/execution.dart';

abstract class BinaryOperatorExecutionNode extends BinaryExecutionNode {
  BinaryOperatorExecutionNode(
    super.lhsTree,
    super.rhsTree, {
    required super.thread,
    required super.scope,
  });

  @override
  Future<TickResult> doTick(
    Execution execution,
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

  dynamic apply();
  bool shortCircuit() => false;
}
