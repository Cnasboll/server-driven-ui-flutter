import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/lazy_execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime/execution_context.dart';
import 'package:server_driven_ui/shql/execution/runtime/runtime.dart';
import 'package:server_driven_ui/shql/parser/parse_tree.dart';
import 'package:server_driven_ui/shql/tokenizer/token.dart';

class LambdaExpressionExecutionNode extends LazyExecutionNode {
  LambdaExpressionExecutionNode(
    this.name,
    super.node, {
    required super.thread,
    required super.scope,
  }) {
    var (userFunction, e) = createUserFunction();
    if (e != null) {
      error = e;
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
    // Verify that first child is a tuple
    if (node.children[0].symbol != Symbols.tuple) {
      return resolveArgumentsFromParseTreeList(
        node.children.sublist(0, node.children.length - 1),
      );
    }
    return resolveArgumentsFromParseTreeList(node.children[0].children);
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
