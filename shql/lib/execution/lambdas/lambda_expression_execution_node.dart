import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/lazy_execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/execution/runtime_error.dart';
import 'package:shql/parser/parse_tree.dart';
import 'package:shql/tokenizer/token.dart';

class LambdaExpressionExecutionNode extends LazyExecutionNode {
  LambdaExpressionExecutionNode(
    this.name,
    super.node, {
    required super.thread,
    required super.scope,
  }) {
    var (userFunction, errorMsg) = createUserFunction();
    if (errorMsg != null) {
      error = RuntimeError.fromParseTree(errorMsg, node);
      return;
    }
    result = userFunction;
    completed = true;
  }

  LambdaExpressionExecutionNode.fromUserFunction(
    this.name,
    super.node,
    UserFunction result, {
    required super.thread,
    required super.scope,
  }) {
    this.result = result;
    completed = true;
  }

  LambdaExpressionExecutionNode.fromNullaryFunction(
    this.name,
    super.node,
    NullaryFunction result, {
    required super.thread,
    required super.scope,
  }) {
    this.result = result;
    completed = true;
  }

  LambdaExpressionExecutionNode.fromUnaryFunction(
    this.name,
    super.node,
    UnaryFunction result, {
    required super.thread,
    required super.scope,
  }) {
    this.result = result;
    completed = true;
  }

  LambdaExpressionExecutionNode.fromBinaryFunction(
    this.name,
    super.node,
    BinaryFunction result, {
    required super.thread,
    required super.scope,
  }) {
    this.result = result;
    completed = true;
  }

  LambdaExpressionExecutionNode.fromTernaryFunction(
    this.name,
    super.node,
    TernaryFunction result, {
    required super.thread,
    required super.scope,
  }) {
    this.result = result;
    completed = true;
  }

  final String name;

  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) async {
    return TickResult.completed;
  }

  (UserFunction?, String?) createUserFunction() {
    // Verify that node has exactly two children
    if (node.children.length != 2) {
      return (
        null,
        "Lambda expression requires exactly two operands, ${node.children.length} given.",
      );
    }

    var (argumentIdentifiers, error) = resolveArgumentIdentifiers();

    if (argumentIdentifiers == null) {
      if (error != null) {
        return (null, error);
      }
      return (null, "Unexpected error resolving argument identifiers.");
    }

    var userFunction = UserFunction(
      identifier: null,
      name: name,
      argumentIdentifiers: argumentIdentifiers,
      scope: scope,
      body: node.children[1],
    );

    return (userFunction, null);
  }

  (List<int>?, String?) resolveArgumentIdentifiers() {
    //  Check what the first child is:
    // - If it's a tuple: direct parameters like () => body or (x, y) => body
    // - If it's a colon: from OBJECT literal like getX: () => body
    //   In this case, colon has [identifier, params] where params can be:
    //   - tuple() for no params
    //   - identifier for single param
    //   - tuple(identifiers...) for multiple params
    // - If it's an identifier: old format without parens
    var firstChild = node.children[0];

    if (firstChild.symbol == Symbols.tuple) {
      // Direct tuple: () => body or (x, y) => body
      return resolveArgumentsFromParseTreeList(firstChild.children);
    } else if (firstChild.symbol == Symbols.colon) {
      // From OBJECT literal: fieldName: (...params) => body
      if (firstChild.children.length < 2) {
        return (null, "Colon node in lambda must have 2 children.");
      }

      var paramsNode = firstChild.children[1];

      if (paramsNode.symbol == Symbols.tuple) {
        // No params or multiple params: () => body or (x, y) => body
        return resolveArgumentsFromParseTreeList(paramsNode.children);
      } else if (paramsNode.symbol == Symbols.identifier) {
        // Single param without parens: (x) => body (parsed as single identifier)
        return resolveArgumentsFromParseTreeList([paramsNode]);
      } else {
        return (
          null,
          "Expected tuple or identifier for lambda parameters in colon node.",
        );
      }
    } else {
      // Old format: multiple arguments without parens like x, y => body
      return resolveArgumentsFromParseTreeList(
        node.children.sublist(0, node.children.length - 1),
      );
    }
  }

  (List<int>?, String?) resolveArgumentsFromParseTreeList(
    List<ParseTree> arguments,
  ) {
    List<int> argumentIdentifiers = [];
    for (var arg in arguments) {
      if (arg.symbol != Symbols.identifier) {
        return (
          null,
          "All arguments in lambda expression must be identifiers.",
        );
      }
      if (arg.children.isNotEmpty) {
        return (null, "Arguments in lambda expression cannot have children.");
      }
      argumentIdentifiers.add(arg.qualifier!);
    }
    return (argumentIdentifiers, null);
  }
}
