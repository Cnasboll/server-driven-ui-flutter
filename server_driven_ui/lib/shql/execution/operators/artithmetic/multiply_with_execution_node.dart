import 'package:server_driven_ui/shql/execution/null_aware_unary_node.dart';

class MultiplyWithExecutionNode extends NullAwareUnaryNode {
  MultiplyWithExecutionNode(
    super.node,
    this.factor, {
    required super.thread,
    required super.scope,
  });

  dynamic factor;

  @override
  Future<dynamic> applyNotNull() async => operandResult * factor;
}
