import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/engine/engine.dart';
import 'package:shql/execution/apriori_execution_node.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/index_to_execution_node.dart';
import 'package:shql/execution/lambdas/binary_function_execution_node.dart';
import 'package:shql/execution/lambdas/nullary_function_execution_node.dart';
import 'package:shql/execution/lambdas/ternary_function_execution_node.dart';
import 'package:shql/execution/lambdas/unary_function_execution_node.dart';
import 'package:shql/execution/lambdas/user_function_execution_node.dart';
import 'package:shql/execution/lazy_execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/execution/runtime_error.dart';
import 'package:shql/tokenizer/token.dart';

class CallExecutionNode extends LazyExecutionNode {
  /// Optional scope for evaluating arguments separately from the callable.
  /// When a call is made via member access (e.g. `Filters.method(arg)`),
  /// the callable is resolved in the object's scope but arguments should
  /// be evaluated in the caller's scope to avoid field-name shadowing.
  final Scope? argumentScope;

  CallExecutionNode(super.node, {required super.thread, required super.scope, this.argumentScope});

  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
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
      error =
          _callableNode!.error ??
          RuntimeError.fromParseTree(
            "Callable entity resolved to null.",
            node.children[0],
          );
      return TickResult.completed;
    }

    if (_argumentsNode == null) {
      _argumentsNode = Engine.createExecutionNode(
        node.children[1],
        thread,
        argumentScope ?? scope,
      );
      return TickResult.delegated;
    }

    if (callNode == null) {
      var (c, error) = createCallNode(callableResult, executionContext);
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

  (ExecutionNode?, RuntimeError?) createCallNode(
    dynamic callableResult,
    ExecutionContext executionContext,
  ) {
    var argumentsResult = _argumentsNode!.result as List;
    var callableResult = _callableNode!.result;
    var argumentCount = argumentsResult.length;

    var lhsIsTuple = node.children[1].symbol == Symbols.tuple;
    var lhsIsList = node.children[1].symbol == Symbols.list;

    if (lhsIsList) {
      return _createIndexerNode(
        callableResult,
        argumentsResult,
        argumentCount,
        executionContext,
      );
    }

    if (!lhsIsTuple || _argumentsNode!.result is! List) {
      return (
        null,
        RuntimeError.fromParseTree(
          "Expected tuple of arguments for function call, got ${_argumentsNode!.result.runtimeType}.",
          node.children[0],
        ),
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
            RuntimeError.fromParseTree(
              "Attempt to use nullary function with $argumentCount argument(s).",
              node.children[0],
            ),
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
            RuntimeError.fromParseTree(
              "Attempt to use unary function with $argumentCount argument(s).",
              node.children[0],
            ),
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
            RuntimeError.fromParseTree(
              "Attempt to use binary function with $argumentCount argument(s).",
              node.children[0],
            ),
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

      var isTernaryFunction = callableResult is TernaryFunction;
      if (isTernaryFunction) {
        if (argumentCount != 3) {
          return (
            null,
            RuntimeError.fromParseTree(
              "Attempt to use ternary function with $argumentCount argument(s).",
              node.children[0],
            ),
          );
        }
        return (
          TernaryFunctionExecutionNode(
            callableResult,
            argumentsResult[0],
            argumentsResult[1],
            argumentsResult[2],
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

  (IndexToExecutionNode?, RuntimeError?) _createIndexerNode(
    dynamic callableResult,
    List argumentsResult,
    int argumentCount,
    ExecutionContext executionContext,
  ) {
    if (argumentCount != 1) {
      return (
        null,
        RuntimeError.fromParseTree(
          "Expected single argument for list index, got $argumentCount.",
          node.children[1],
        ),
      );
    }

    if (callableResult is! List &&
        callableResult is! Map &&
        callableResult is! String) {
      return (
        null,
        RuntimeError.fromParseTree(
          "${callableResult.runtimeType} used with an indexer.",
          node.children[1],
        ),
      );
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
