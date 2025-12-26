import 'package:server_driven_ui/shql/execution/null_aware_unary_node.dart';

class UnaryMinusExecutionNode extends NullAwareUnaryNode {
  UnaryMinusExecutionNode(
    super.node, {
    required super.thread,
    required super.scope,
  });

  @override
  Future<dynamic> applyNotNull() async => -operandResult;
}
