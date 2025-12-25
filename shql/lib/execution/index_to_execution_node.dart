import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';
import 'package:shql/execution/runtime_error.dart';

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
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) {
    try {
      result = indexable[index];
    } on RangeError {
      final type = indexable.runtimeType;
      final len = (indexable is List) ? indexable.length : (indexable is String ? indexable.length : '?');
      error = RuntimeError('Index out of range: [$index] on $type (length $len)');
    }
    return Future.value(TickResult.completed);
  }

  void assign(dynamic value) {
    try {
      indexable[index] = value;
    } on RangeError {
      final type = indexable.runtimeType;
      final len = (indexable is List) ? indexable.length : (indexable is String ? indexable.length : '?');
      error = RuntimeError('Index out of range: [$index] = $value on $type (length $len)');
    }
  }
}
