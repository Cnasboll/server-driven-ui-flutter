import 'package:server_driven_ui/shql/execution/lazy_parent_execution_node.dart';

class ListLiteralNode extends LazyParentExecutionNode {
  ListLiteralNode(super.node, {required super.thread, required super.scope});
  @override
  dynamic evaluate() => children!.map((c) => c.result).toList();
}
