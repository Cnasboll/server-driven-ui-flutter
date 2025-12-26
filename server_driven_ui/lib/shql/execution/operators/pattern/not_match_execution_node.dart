import 'package:server_driven_ui/shql/execution/operators/pattern/regexp_execution_node.dart';

class NotMatchExecutionNode extends RegexpExecutionNode {
  NotMatchExecutionNode(
    super.rhsTree,
    super.lhsTree, {
    required super.thread,
    required super.scope,
  });

  @override
  bool applyNotNull() => !matches(lhsResult, rhsResult);
}
