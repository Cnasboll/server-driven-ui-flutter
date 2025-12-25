import 'dart:math';
import 'package:server_driven_ui/shql/execution/null_aware_binary_node.dart';

class ExponentiationExecutionNode extends NullAwareBinaryNode {
  ExponentiationExecutionNode(
    super.lhsTree,
    super.rhsTree, {
    required super.thread,
    required super.scope,
  });

  @override
  dynamic applyNotNull() => pow(lhsResult, rhsResult);
}
