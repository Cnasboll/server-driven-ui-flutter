import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/engine/engine.dart';
import 'package:server_driven_ui/shql/execution/apriori_execution_node.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/index_to_execution_node.dart';
import 'package:server_driven_ui/shql/execution/lambdas/binary_function_execution_node.dart';
import 'package:server_driven_ui/shql/execution/lambdas/nullary_function_execution_node.dart';
import 'package:server_driven_ui/shql/execution/lambdas/unary_function_execution_node.dart';
import 'package:server_driven_ui/shql/execution/lambdas/user_function_execution_node.dart';
import 'package:server_driven_ui/shql/execution/lazy_execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime.dart';
import 'package:server_driven_ui/shql/tokenizer/token.dart';

class CallExecutionNode extends LazyExecutionNode {
  CallExecutionNode(super.node, {required super.thread, required super.scope});

  @override
  Future<TickResult> doTick(
    Runtime runtime,
    CancellationToken? cancellationToken,
  ) async {
    // We need to verify that the lhs is a callable entity, i.e. an identifier or a lambda expression
    if (_callableNode == null) {
      _callableNode = Engine.createExecutionNode(
        node.children[0],
        thread,
        scope,
      );
      return TickResult.delegated;
    }

    var callableResult = _callableNode!.result;

    if (callableResult == null) {
      error = _callableNode!.error ?? "Callable entity resolved to null.";
      return TickResult.completed;
    }

    if (_argumentsNode == null) {
      _argumentsNode = Engine.createExecutionNode(
        node.children[1],
        thread,
        scope,
      );
      return TickResult.delegated;
    }

    if (callNode == null) {
      var (c, error) = createCallNode(callableResult);
      if (error != null) {
        this.error = error;
        return TickResult.completed;
      }
      if (c == null) {
        return TickResult.completed;
      }
      callNode = c;

      if (callNode!.completed) {
        result = callNode!.result;
        error ??= callNode!.error;
        return TickResult.completed;
      }

      return TickResult.delegated;
    }
    result = callNode!.result;
    error ??= callNode!.error;
    return TickResult.completed;
  }

  (ExecutionNode?, String?) createCallNode(dynamic callableResult) {
    var argumentsResult = _argumentsNode!.result as List;
    var callableResult = _callableNode!.result;
    var argumentCount = argumentsResult.length;

    var lhsIsTuple = node.children[1].symbol == Symbols.tuple;
    var lhsIsList = node.children[1].symbol == Symbols.list;

    if (lhsIsList) {
      return _createIndexerNode(callableResult, argumentsResult, argumentCount);
    }

    if (!lhsIsTuple || _argumentsNode!.result is! List) {
      return (
        null,
        "Expected tuple of arguments for function call, got ${_argumentsNode!.result.runtimeType}.",
      );
    }

    var isCallable = callableResult is Callable;
    if (isCallable) {
      var isUserFunction = callableResult is UserFunction;
      if (isUserFunction) {
        return (
          UserFunctionExecutionNode(
            callableResult,
            argumentsResult,
            thread: thread,
            scope: scope,
          ),
          null,
        );
      }
      var isNullaryFunction = callableResult is NullaryFunction;
      if (isNullaryFunction) {
        if (argumentCount != 0) {
          return (
            null,
            "Attempt to use nullary function with $argumentCount argument(s).",
          );
        }
        return (
          NullaryFunctionExecutionNode(
            callableResult,
            thread: thread,
            scope: scope,
          ),
          null,
        );
      }

      var isUnaryFunction = callableResult is UnaryFunction;
      if (isUnaryFunction) {
        if (argumentCount != 1) {
          return (
            null,
            "Attempt to use unary function with $argumentCount argument(s).",
          );
        }
        return (
          UnaryFunctionExecutionNode(
            callableResult,
            argumentsResult[0],
            thread: thread,
            scope: scope,
          ),
          null,
        );
      }

      var isBinaryFunction = callableResult is BinaryFunction;
      if (isBinaryFunction) {
        if (argumentCount != 2) {
          return (
            null,
            "Attempt to use binary function with $argumentCount argument(s).",
          );
        }
        return (
          BinaryFunctionExecutionNode(
            callableResult,
            argumentsResult[0],
            argumentsResult[1],
            thread: thread,
            scope: scope,
          ),
          null,
        );
      }
    }
    // Special case: Treat non-callable with arguments as multiplication
    var product = callableResult;
    for (var factor in argumentsResult) {
      product *= factor;
    }
    // TODO: Check if lhs is constant or variable, or anything else and list is empty
    //"Attempt to use ${isConstant ? "constant" : "variable"} $name as a function: ($argumentCount) argument(s) given.",
    return (AprioriExecutionNode(product, thread: thread, scope: scope), null);
  }

  (IndexToExecutionNode?, String?) _createIndexerNode(
    dynamic callableResult,
    List argumentsResult,
    int argumentCount,
  ) {
    if (argumentCount != 1) {
      return (
        null,
        "Expected single argument for list index, got $argumentCount.",
      );
    }

    if (callableResult is! List) {
      return (null, "${callableResult.runtimeType} used with an indexer.");
    }

    return (
      IndexToExecutionNode(
        callableResult,
        argumentsResult[0],
        thread: thread,
        scope: scope,
      ),
      null,
    );
  }

  ExecutionNode? _callableNode;
  ExecutionNode? _argumentsNode;
  ExecutionNode? callNode;
}
