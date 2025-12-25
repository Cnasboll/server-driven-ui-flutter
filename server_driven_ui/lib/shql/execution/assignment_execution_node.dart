import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/engine/engine.dart';
import 'package:server_driven_ui/shql/execution/index_to_execution_node.dart';
import 'package:server_driven_ui/shql/execution/lambdas/call_execution_node.dart';
import 'package:server_driven_ui/shql/execution/set_variable_execution_node.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/lazy_execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime.dart';
import 'package:server_driven_ui/shql/parser/parse_tree.dart';
import 'package:server_driven_ui/shql/tokenizer/token.dart';

class AssignmentExecutionNode extends LazyExecutionNode {
  AssignmentExecutionNode(
    super.node, {
    required super.thread,
    required super.scope,
  });

  @override
  Future<TickResult> doTick(
    Runtime runtime,
    CancellationToken? cancellationToken,
  ) async {
    if (_rhs == null) {
      var (rhs, e) = createRhs(runtime);
      if (e != null) {
        error = e;
        return TickResult.completed;
      }
      if (rhs == null) {
        return TickResult.completed;
      }
      _rhs = rhs;
      return TickResult.delegated;
    }

    if (_lhs == null) {
      var (lhs, error) = createLhs(runtime);
      if (error != null) {
        this.error = error;
        return TickResult.completed;
      }
      _lhs = lhs;
      return TickResult.delegated;
    }

    if (_lhs is CallExecutionNode) {
      var callNode = (_lhs as CallExecutionNode).callNode;
      if (callNode is IndexToExecutionNode) {
        // Check if lhs is a list member eg: arr[i] := 5 meaning Symbols.list
        callNode.assign(_rhs!.result);
      }
    }

    error ??= _lhs!.error;
    result = _rhs!.result;
    return TickResult.completed;
  }

  (ExecutionNode?, String?) createLhs(Runtime runtime) {
    if (node.children[0].symbol == Symbols.identifier) {
      return (
        SetVariableExecutionNode(
          node.children[0],
          _rhs!.result,
          thread: thread,
          scope: scope,
        ),
        null,
      );
    }
    return (Engine.createExecutionNode(node.children[0], thread, scope), null);
  }

  (ExecutionNode?, String?) createRhs(Runtime runtime) {
    // Verify that node has exactly two children
    if (node.children.length != 2) {
      return (
        null,
        "Assignment operator requires exactly two operands, ${node.children.length} given.",
      );
    }

    // Check if lhs is a function "call" with an argument list (for function definition)
    // Eg: f(x) := x + 1 meaning  Symbols.tuple
    // or assigning to list members eg: arr[i] := 5 meaning Symbols.list
    // If it is a function definition, all arguments must be identifiers without any children themselves
    var targetNode = node.children[0];
    if (targetNode.symbol == Symbols.call) {
      var argumentsNode = targetNode.children[1];
      if (argumentsNode.symbol == Symbols.tuple) {
        var identifierChild = targetNode.children[0];
        if (identifierChild.symbol != Symbols.identifier) {
          return (
            null,
            "Function definition assignment requires identifier as target.",
          );
        }
        var identifier = identifierChild.qualifier!;
        var name = runtime.identifiers.constants[identifier];

        if (defineUserFunction(name, argumentsNode, runtime, identifier)) {
          return (null, null);
        } else {
          return (null, "Cannot create user function for identifier $name.");
        }
      }
    }

    return (Engine.createExecutionNode(node.children[1], thread, scope)!, null);
  }

  bool defineUserFunction(
    String name,
    ParseTree argumentsNode,
    Runtime runtime,
    int identifier,
  ) {
    var arguments = argumentsNode.children;
    List<int> argumentIdentifiers = [];
    for (var arg in arguments) {
      if (arg.symbol != Symbols.identifier) {
        error = "All arguments in function definition must be identifiers.";
        return true;
      }
      if (arg.children.isNotEmpty) {
        error = "Arguments in function definition cannot have children.";
        return true;
      }
      argumentIdentifiers.add(arg.qualifier!);
    }
    var userFunction = UserFunction(
      identifier: identifier,
      name: name,
      argumentIdentifiers: argumentIdentifiers,
      scope: scope,
      body: node.children[1],
    );
    scope.members.defineUserFunction(identifier, userFunction);
    result = userFunction;
    return true;
  }

  bool assignToListMember(
    String name,
    ParseTree indexNode,
    Runtime runtime,
    int identifier,
  ) {
    var indexes = indexNode.children;
    List<int> argumentIdentifiers = [];
    for (var arg in indexes) {
      if (arg.symbol != Symbols.identifier) {
        error = "All arguments in function definition must be identifiers.";
        return true;
      }
      if (arg.children.isNotEmpty) {
        error = "Arguments in function definition cannot have children.";
        return true;
      }
      argumentIdentifiers.add(arg.qualifier!);
    }
    var userFunction = UserFunction(
      identifier: identifier,
      name: name,
      argumentIdentifiers: argumentIdentifiers,
      scope: scope,
      body: node.children[1],
    );
    scope.members.defineUserFunction(identifier, userFunction);
    result = userFunction;
    return true;
  }

  ExecutionNode? _lhs;
  ExecutionNode? _rhs;
}
