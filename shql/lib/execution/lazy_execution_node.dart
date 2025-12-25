import 'package:shql/execution/execution_node.dart';
import 'package:shql/parser/parse_tree.dart';

abstract class LazyExecutionNode extends ExecutionNode {
  final ParseTree node;
  LazyExecutionNode(this.node, {required super.thread, required super.scope});
}
