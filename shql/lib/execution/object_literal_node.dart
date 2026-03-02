import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/engine/engine.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/lazy_execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/execution/runtime_error.dart';
import 'package:shql/parser/parse_tree.dart';
import 'package:shql/tokenizer/token.dart';

class ObjectLiteralNode extends LazyExecutionNode {
  List<ExecutionNode>? children;
  Object? obj;
  Scope? objectScope;

  ObjectLiteralNode(super.node, {required super.thread, required super.scope});

  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) async {
    if (obj == null) {
      // Step 1: Create the Object and a Scope that wraps it
      // The scope inherits from the current scope (for closures)
      obj = Object();

      // Inject THIS as a self-reference on the object. Set before field
      // evaluation so lambdas (methods) can capture it via scope resolution.
      // THIS is a variable, not a constant, but it lives on the object scope
      // so it shadows any outer "THIS" — and each object has its own THIS.
      final thisId = executionContext.runtime.identifiers.include("THIS");
      obj!.setVariable(thisId, obj);

      objectScope = Scope(obj!, constants: scope.constants, parent: scope);

      // Step 2: Create execution nodes for all values using the object's scope
      // This way, lambdas will capture the object scope and can access object members
      List<ExecutionNode> r = [];
      for (var child in node.children.reversed) {
        ExecutionNode? valueNode;

        if (child.symbol == Symbols.colon) {
          // Simple key:value pair - create execution node for value (right side)
          valueNode = Engine.createExecutionNode(
            child.children[1],
            thread,
            objectScope!, // Use object's scope!
          );
        } else if (child.symbol == Symbols.lambdaExpression) {
          // Lambda expression - create execution node for the entire lambda
          valueNode = Engine.createExecutionNode(
            child,
            thread,
            objectScope!, // Use object's scope!
          );
        } else if (child.symbol == Symbols.assignment) {
          // Assignment node wrapping a lambda (happens when lambda body contains assignment)
          // e.g., setX: (newX) => x := newX
          // Due to operator precedence, this parses as: assignment(lambda, rhs)
          // We need to restructure it as: lambda with assignment body
          var lhs = child.children[0];
          if (lhs.symbol == Symbols.lambdaExpression) {
            // Restructure: create a new lambda with assignment as the body
            var lambdaColon = lhs.children[0]; // colon(name: params)
            var lambdaPartialBody =
                lhs.children[1]; // what parser thought was body
            var assignmentRhs = child.children[1]; // actual RHS of assignment

            // Create a new assignment node with correct structure
            var newAssignment = ParseTree.withChildren(
              Symbols.assignment,
              [lambdaPartialBody, assignmentRhs],
              child.tokens,
              sourceCode: child.sourceCode,
            );

            // Create a new lambda with the assignment as its body
            var newLambda = ParseTree.withChildren(
              Symbols.lambdaExpression,
              [lambdaColon, newAssignment],
              lhs.tokens,
              sourceCode: lhs.sourceCode,
            );

            valueNode = Engine.createExecutionNode(
              newLambda,
              thread,
              objectScope!,
            );
          } else {
            // Not a lambda assignment, execute as normal assignment
            valueNode = Engine.createExecutionNode(child, thread, objectScope!);
          }
        } else {
          error = RuntimeError.fromParseTree(
            'Object literal children must be identifier:value pairs.',
            child,
          );
          return TickResult.completed;
        }

        if (valueNode == null) {
          error = RuntimeError.fromParseTree(
            'Failed to create execution node for value.',
            child,
          );
          return TickResult.completed;
        }

        r.add(valueNode);
      }
      children = r.reversed.toList();
      return TickResult.delegated;
    }

    // Step 3: Populate the object with all the evaluated values
    for (int i = 0; i < children!.length; i++) {
      var childNode = node.children[i];

      // Extract the colon node (which contains the identifier)
      ParseTree colonNode;
      if (childNode.symbol == Symbols.colon) {
        colonNode = childNode;
      } else if (childNode.symbol == Symbols.lambdaExpression) {
        // Lambda: first child is colon
        colonNode = childNode.children[0];
      } else if (childNode.symbol == Symbols.assignment) {
        // Assignment wrapping lambda: assignment -> lambdaExpression -> colon
        colonNode = childNode.children[0].children[0];
      } else {
        error = RuntimeError.fromParseTree(
          'Object literal child must be colon, lambda, or assignment',
          childNode,
        );
        return TickResult.completed;
      }

      var identifierNode = colonNode.children[0];

      if (identifierNode.symbol != Symbols.identifier) {
        error = RuntimeError.fromParseTree(
          'Object literal key must be an identifier',
          identifierNode,
        );
        return TickResult.completed;
      }

      // Get the identifier name as a string
      String fieldName = identifierNode.tokens.first.lexeme.toUpperCase();
      int fieldId = executionContext.runtime.identifiers.include(fieldName);

      // Get the value (right side of colon or lambda result)
      var value = children![i].result;

      // Set the field on the object
      obj!.setVariable(fieldId, value);
    }

    result = obj;
    return TickResult.completed;
  }
}
