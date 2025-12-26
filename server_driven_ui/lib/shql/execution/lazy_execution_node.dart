import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/parser/parse_tree.dart';

abstract class LazyExecutionNode extends ExecutionNode {
  final ParseTree node;
  LazyExecutionNode(this.node, {required super.thread, required super.scope});
}
