import 'package:server_driven_ui/shql/execution/null_aware_binary_node.dart';

class LessThanOrEqualExecutionNode extends NullAwareBinaryNode {
  LessThanOrEqualExecutionNode(
    super.lhsTree,
    super.rhsTree, {
    required super.thread,
    required super.scope,
  });

  @override
  bool applyNotNull() => lhsResult <= rhsResult;
}
