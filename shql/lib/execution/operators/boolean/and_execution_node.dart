import 'package:shql/execution/operators/boolean/boolean_exeuction_node.dart';

class AndExecutionNode extends BooleanExecutionNode {
  AndExecutionNode(
    super.lhsTree,
    super.rhsTree, {
    required super.thread,
    required super.scope,
  });

  @override
  bool shortCircuit() {
    if (!lhsBoolResult) {
      result = false;
      return true;
    }
    return false;
  }

  @override
  bool apply() => lhsBoolResult && rhsBoolResult;
}
