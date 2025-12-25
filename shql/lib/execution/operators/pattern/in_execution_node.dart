import 'package:shql/execution/null_aware_binary_node.dart';

class InExecutionNode extends NullAwareBinaryNode {
  InExecutionNode(
    super.lhsTree,
    super.rhsTree, {
    required super.thread,
    required super.scope,
  });

  @override
  bool applyNotNull() {
    if (rhsResult is List || rhsResult is Set) {
      return rhsResult.contains(lhsResult);
    }
    if (rhsResult is Iterable) {
      for (var item in rhsResult) {
        if (item == lhsResult) {
          return true;
        }
      }
      return false;
    }
    var lhs = lhsResult is String ? lhsResult : lhsResult.toString();
    var rhs = rhsResult is String ? rhsResult : rhsResult.toString();
    return rhs.contains(lhs);
  }
}
