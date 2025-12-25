import 'package:shql/execution/null_aware_unary_node.dart';

class NotExecutionNode extends NullAwareUnaryNode {
  NotExecutionNode(super.node, {required super.thread, required super.scope});

  @override
  Future<dynamic> applyNotNull() async =>
      operandResult is bool ? !operandResult : operandResult == 0;
}
