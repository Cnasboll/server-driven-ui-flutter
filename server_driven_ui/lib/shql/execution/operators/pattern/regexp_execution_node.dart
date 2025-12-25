import 'package:server_driven_ui/shql/execution/null_aware_binary_node.dart';

abstract class RegexpExecutionNode extends NullAwareBinaryNode {
  RegexpExecutionNode(
    super.lhsTree,
    super.rhsTree, {
    required super.thread,
    required super.scope,
  });

  bool matches(dynamic lhsResult, dynamic rhsResult) {
    var regex = RegExp(rhsResult.toString(), caseSensitive: false);
    return regex.hasMatch(lhsResult.toString());
  }
}
