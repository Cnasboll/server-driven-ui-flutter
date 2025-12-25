import 'package:shql/execution/null_aware_binary_node.dart';

class AdditionExecutionNode extends NullAwareBinaryNode {
  AdditionExecutionNode(
    super.lhsTree,
    super.rhsTree, {
    required super.thread,
    required super.scope,
  });

  @override
  dynamic applyNotNull() {
    // List concatenation: spread into List<dynamic> to avoid type mismatch
    // (e.g. List<Object> + List<dynamic> throws TypeError in Dart).
    if (lhsResult is List && rhsResult is List) {
      return [...lhsResult, ...rhsResult];
    }
    return lhsResult + rhsResult;
  }
}
