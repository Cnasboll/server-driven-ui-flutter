import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/lazy_execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime.dart';
import 'package:server_driven_ui/shql/parser/constants_set.dart';

class ConstantNode<T> extends LazyExecutionNode {
  ConstantNode(super.node, {required super.thread, required super.scope});

  @override
  Future<TickResult> doTick(
    Runtime runtime,
    CancellationToken? cancellationToken,
  ) async {
    Scope? currentScope = scope;
    ConstantsTable<dynamic>? constants;
    while (currentScope != null) {
      constants ??= currentScope.constants;
      if (constants != null) {
        break;
      }
      currentScope = currentScope.parent;
    }
    if (constants == null) {
      error = "No constants table found in scope chain.";
      return TickResult.completed;
    }
    result = constants.getByIndex(node.qualifier!);
    return TickResult.completed;
  }
}
