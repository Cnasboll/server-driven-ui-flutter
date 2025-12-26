import 'package:server_driven_ui/shql/execution/null_aware_binary_node.dart';

class ModulusExecutionNode extends NullAwareBinaryNode {
  ModulusExecutionNode(
    super.lhsTree,
    super.rhsTree, {
    required super.thread,
    required super.scope,
  });

  @override
  dynamic applyNotNull() => lhsResult % rhsResult;
}
