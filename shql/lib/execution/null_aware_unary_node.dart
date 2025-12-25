import 'package:shql/execution/unary_execution_node.dart';

abstract class NullAwareUnaryNode extends UnaryExecutionNode {
  NullAwareUnaryNode(super.node, {required super.thread, required super.scope});

  @override
  Future<dynamic> apply() async {
    if (operandResult == null) {
      return null;
    }
    return applyNotNull();
  }

  Future<dynamic> applyNotNull();
}
