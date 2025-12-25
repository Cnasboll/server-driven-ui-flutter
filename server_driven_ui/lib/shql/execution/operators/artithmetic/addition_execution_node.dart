import 'package:server_driven_ui/shql/execution/null_aware_binary_node.dart';

class AdditionExecutionNode extends NullAwareBinaryNode {
  AdditionExecutionNode(
    super.lhsTree,
    super.rhsTree, {
    required super.thread,
    required super.scope,
  });

  @override
  dynamic applyNotNull() => lhsResult + rhsResult;
}
