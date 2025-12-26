import 'package:server_driven_ui/shql/engine/engine.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/parser/parse_tree.dart';

abstract class BinaryExecutionNode extends ExecutionNode {
  BinaryExecutionNode(
    this.lhsTree,
    this.rhsTree, {
    required super.thread,
    required super.scope,
  });

  ParseTree lhsTree;
  ParseTree rhsTree;

  ExecutionNode? lhs;
  ExecutionNode pushLhs() {
    lhs = Engine.createExecutionNode(lhsTree, thread, scope);
    return lhs!;
  }

  dynamic get lhsResult => lhs?.result;

  ExecutionNode? rhs;
  ExecutionNode pushRhs() {
    rhs = Engine.createExecutionNode(rhsTree, thread, scope);
    return rhs!;
  }

  dynamic get rhsResult => rhs?.result;
}
