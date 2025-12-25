import 'package:shql/execution/null_aware_binary_node.dart';

class IndexerExecutionNode extends NullAwareBinaryNode {
  IndexerExecutionNode(
    super.lhs,
    super.rhs, {
    required super.thread,
    required super.scope,
  });

  @override
  dynamic applyNotNull() async => lhsResult[rhsResult];
}
