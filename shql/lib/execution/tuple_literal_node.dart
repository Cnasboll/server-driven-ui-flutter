import 'package:shql/execution/lazy_parent_execution_node.dart';

class TupleLiteralNode extends LazyParentExecutionNode {
  TupleLiteralNode(super.node, {required super.thread, required super.scope});
  @override
  dynamic evaluate() => children!.map((c) => c.result).toList();
}
