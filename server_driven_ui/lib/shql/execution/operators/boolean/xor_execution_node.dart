import 'package:server_driven_ui/shql/execution/operators/boolean/boolean_exeuction_node.dart';

class XorExecutionNode extends BooleanExecutionNode {
  XorExecutionNode(
    super.lhsTree,
    super.rhsTree, {
    required super.thread,
    required super.scope,
  });

  @override
  bool shortCircuit() {
    return false;
  }

  @override
  bool apply() => lhsBoolResult ^ rhsBoolResult;
}
