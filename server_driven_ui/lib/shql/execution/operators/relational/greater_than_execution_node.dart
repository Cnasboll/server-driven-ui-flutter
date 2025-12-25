import 'package:server_driven_ui/shql/execution/null_aware_binary_node.dart';

class GreaterThanExecutionNode extends NullAwareBinaryNode {
  GreaterThanExecutionNode(
    super.lhsTree,
    super.rhsTree, {
    required super.thread,
    required super.scope,
  });

  @override
  bool applyNotNull() => lhsResult > rhsResult;
}
