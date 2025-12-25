import 'package:shql/execution/binary_operator_execution_node.dart';

class NameValuePairExecutionNode extends BinaryOperatorExecutionNode {
  NameValuePairExecutionNode(
    super.lhsTree,
    super.rhsTree, {
    required super.thread,
    required super.scope,
  });

  @override
  dynamic apply() => (lhsResult, rhsResult);
}
