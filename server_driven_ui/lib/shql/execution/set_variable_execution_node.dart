import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/lazy_execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime/execution.dart';
import 'package:server_driven_ui/shql/execution/runtime/runtime.dart';
import 'package:server_driven_ui/shql/tokenizer/token.dart';

class SetVariableExecutionNode extends LazyExecutionNode {
  SetVariableExecutionNode(
    super.node,
    this.rhsValue, {
    required super.thread,
    required super.scope,
  });

  @override
  Future<TickResult> doTick(
    Execution execution,
    CancellationToken? cancellationToken,
  ) async {
    // Verify that first child is an identifier
    if (node.symbol != Symbols.identifier) {
      error = "Left-hand side of assignment must be an identifier.";
      return TickResult.completed;
    }

    var identifier = node.qualifier!;

    var (target, containingScope, isConstant) = scope.resolveIdentifier(
      identifier,
    );

    if (isConstant) {
      error = "Cannot assign to constant.";
      return TickResult.completed;
    }

    if (rhsValue is UserFunction) {
      var (containingScope, _, error) = scope.defineUserFunction(
        identifier,
        rhsValue,
      );
      if (error != null) {
        this.error = error;
        return TickResult.completed;
      }
    } else {
      var (containingScope, error) = scope.setVariable(identifier, rhsValue);
      if (error != null) {
        this.error = error;
        return TickResult.completed;
      }
    }

    result = rhsValue;
    return TickResult.completed;
  }

  final dynamic rhsValue;
}
