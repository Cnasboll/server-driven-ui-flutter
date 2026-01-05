import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/lazy_execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime/execution_context.dart';
import 'package:server_driven_ui/shql/execution/runtime/runtime.dart';
import 'package:server_driven_ui/shql/execution/runtime_error.dart';
import 'package:server_driven_ui/shql/parser/constants_set.dart';

class ConstantNode<T> extends LazyExecutionNode {
  ConstantNode(super.node, {required super.thread, required super.scope});

  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
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
      error = RuntimeError.fromParseTree(
        "No constants table found in scope chain.",
        node,
        sourceCode: executionContext.sourceCode,
      );
      return TickResult.completed;
    }
    result = constants.getByIndex(node.qualifier!);
    return TickResult.completed;
  }
}
