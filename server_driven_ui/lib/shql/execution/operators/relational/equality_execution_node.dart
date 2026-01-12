import 'package:server_driven_ui/shql/execution/binary_operator_execution_node.dart';

class EqualityExecutionNode extends BinaryOperatorExecutionNode {
  EqualityExecutionNode(
    super.lhsTree,
    super.rhsTree, {
    required super.thread,
    required super.scope,
  });

  @override
  bool apply() => lhsResult == rhsResult;
}
