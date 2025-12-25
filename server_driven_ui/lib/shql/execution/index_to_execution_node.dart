import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime.dart';

class IndexToExecutionNode extends ExecutionNode {
  IndexToExecutionNode(
    this.indexable,
    this.index, {
    required super.thread,
    required super.scope,
  });

  dynamic indexable;
  dynamic index;

  @override
  Future<TickResult> doTick(
    Runtime runtime,
    CancellationToken? cancellationToken,
  ) {
    result = indexable[index];
    return Future.value(TickResult.completed);
  }

  void assign(dynamic value) {
    indexable[index] = value;
  }
}
