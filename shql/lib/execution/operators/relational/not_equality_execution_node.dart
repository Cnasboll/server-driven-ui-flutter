import 'package:shql/execution/binary_operator_execution_node.dart';

class NotEqualityExecutionNode extends BinaryOperatorExecutionNode {
  NotEqualityExecutionNode(
    super.lhsTree,
    super.rhsTree, {
    required super.thread,
    required super.scope,
  });

  @override
  bool apply() => lhsResult != rhsResult;
}
