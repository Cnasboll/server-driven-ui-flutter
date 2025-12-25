import 'package:shql/execution/null_aware_binary_node.dart';

class DivisionExecutionNode extends NullAwareBinaryNode {
  DivisionExecutionNode(
    super.lhsTree,
    super.rhsTree, {
    required super.thread,
    required super.scope,
  });

  @override
  dynamic applyNotNull() => lhsResult / rhsResult;
}
