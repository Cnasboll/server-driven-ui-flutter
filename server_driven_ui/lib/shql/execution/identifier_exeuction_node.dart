import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/lambdas/lambda_expression_execution_node.dart';
import 'package:server_driven_ui/shql/execution/lambdas/nullary_function_execution_node.dart';
import 'package:server_driven_ui/shql/execution/lazy_execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime/execution_context.dart';
import 'package:server_driven_ui/shql/execution/runtime/runtime.dart';

class IdentifierExecutionNode extends LazyExecutionNode {
  IdentifierExecutionNode(
    super.node, {
    required super.thread,
    required super.scope,
  });

  ExecutionNode? _childNode;

  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) async {
    if (_childNode == null) {
      var (childNode, value, error) = createChildNode(executionContext);
      if (error != null) {
        this.error = error;
        return TickResult.completed;
      }
      if (childNode == null) {
        result = value;
        return TickResult.completed;
      }
      _childNode = childNode;
      return TickResult.delegated;
    }

    result = _childNode!.result;
    error ??= _childNode!.error;
    return TickResult.completed;
  }

  (ExecutionNode?, dynamic, String?) createChildNode(
    ExecutionContext execution,
  ) {
    var identifier = node.qualifier!;
    var name = execution.runtime.identifiers.constants[identifier];

    // A identifier can have 0 or 1 chhildren
    if (node.children.length > 1) {
      return (
        null,
        null,
        "Identifier $name can have at most one child, ${node.children.length} given.",
      );
    }

    // Try to resolve identifier (variables shadow constants, walks parent chain)
    var (value, containingScope, isConstant) = scope.resolveIdentifier(
      identifier,
    );
    var resolved = containingScope != null;
    var isUserFunction = resolved && value is UserFunction;
    if (isUserFunction) {
      return (
        LambdaExpressionExecutionNode.fromUserFunction(
          name,
          node,
          value,
          thread: thread,
          scope: scope,
        ),
        null,
        null,
      );
    }

    if (resolved) {
      // If identifier resolved to a value, return it
      return (null, value, null);
    }

    var nullaryFunction = resolved
        ? null
        : execution.runtime.getNullaryFunction(name);

    if (nullaryFunction != null) {
      return (
        NullaryFunctionExecutionNode(
          NullaryFunction(
            name: name,
            identifier: identifier,
            function: nullaryFunction,
          ),
          thread: thread,
          scope: scope,
        ),
        null,
        null,
      );
    }

    var unaryFunction = execution.runtime.getUnaryFunction(identifier);

    if (unaryFunction != null) {
      return (
        LambdaExpressionExecutionNode.fromUnaryFunction(
          name,
          node,
          UnaryFunction(
            name: name,
            identifier: identifier,
            function: unaryFunction,
          ),
          thread: thread,
          scope: scope,
        ),
        null,
        null,
      );
    }

    var binaryFunction = execution.runtime.getBinaryFunction(identifier);

    if (binaryFunction != null) {
      return (
        LambdaExpressionExecutionNode.fromBinaryFunction(
          name,
          node,
          BinaryFunction(
            name: name,
            identifier: identifier,
            function: binaryFunction,
          ),
          thread: thread,
          scope: scope,
        ),
        null,
        null,
      );
    }

    return (
      null,
      null,
      '''Unidentified identifier "$name" used as a constant.

Hint: enclose strings in quotes, e.g.          name ~ "Batman"       rather than:     name ~ Batman

''',
    );
  }
}
