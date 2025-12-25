import 'package:shql/execution/binary_operator_execution_node.dart';

abstract class NullAwareBinaryNode extends BinaryOperatorExecutionNode {
  NullAwareBinaryNode(
    super.lhsTree,
    super.rhsTree, {
    required super.thread,
    required super.scope,
  });

  @override
  dynamic apply() {
    if (lhsResult == null || rhsResult == null) {
      return null;
    }
    return applyNotNull();
  }

  dynamic applyNotNull();

  @override
  bool shortCircuit() {
    if (lhsResult == null) {
      result = null;
      return true;
    }
    return false;
  }
}
