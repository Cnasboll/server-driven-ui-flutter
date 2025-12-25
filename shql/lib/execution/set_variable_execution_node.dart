import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/lazy_execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/execution/runtime_error.dart';
import 'package:shql/tokenizer/token.dart';

class SetVariableExecutionNode extends LazyExecutionNode {
  SetVariableExecutionNode(
    super.node,
    this.rhsValue, {
    required super.thread,
    required super.scope,
  });

  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) async {
    // Verify that first child is an identifier
    if (node.symbol != Symbols.identifier) {
      error = RuntimeError.fromParseTree(
        "Left-hand side of assignment must be an identifier.",
        node,
      );
      return TickResult.completed;
    }

    var identifier = node.qualifier!;

    var (target, containingScope, isConstant) = scope.resolveIdentifier(
      identifier,
    );

    if (isConstant) {
      error = RuntimeError.fromParseTree("Cannot assign to constant.", node);
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
