import 'package:shql/execution/operators/boolean/boolean_exeuction_node.dart';

class OrExecutionNode extends BooleanExecutionNode {
  OrExecutionNode(
    super.lhsTree,
    super.rhsTree, {
    required super.thread,
    required super.scope,
  });

  @override
  bool shortCircuit() {
    if (lhsBoolResult) {
      result = true;
      return true;
    }
    return false;
  }

  @override
  bool apply() => lhsBoolResult || rhsBoolResult;
}
