import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/engine/engine.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/identifier_exeuction_node.dart';
import 'package:shql/execution/lazy_execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/execution/runtime_error.dart';
import 'package:shql/parser/constants_set.dart';
import 'package:shql/tokenizer/token.dart';

class MemberAccessExecutionNode extends LazyExecutionNode {
  MemberAccessExecutionNode(
    super.node, {
    required super.thread,
    required super.scope,
  });

  ExecutionNode? _leftNode;
  ExecutionNode? _rightNode;
  ConstantsTable<String>? _identifiers;

  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) async {
    // Store identifiers table for use in assign() method
    _identifiers ??= executionContext.runtime.identifiers;
    if (node.children.length != 2) {
      error = RuntimeError.fromParseTree(
        'Member access must have exactly 2 children',
        node,
      );
      return TickResult.completed;
    }

    if (_leftNode == null) {
      // Left side can be any expression (identifier, member access, etc.)
      _leftNode = Engine.createExecutionNode(node.children[0], thread, scope);
      if (_leftNode == null) {
        error = RuntimeError.fromParseTree(
          'Failed to create execution node for left side of member access',
          node.children[0],
        );
        return TickResult.completed;
      }
      return TickResult.delegated;
    }

    var leftResult = _leftNode!.result;

    // Convert Object to Scope if needed
    Scope rightScope;
    if (leftResult is Scope) {
      rightScope = leftResult;
    } else if (leftResult is Object) {
      // Wrap Object in a Scope to allow member lookup.
      // Parent must point to the enclosing scope so that call arguments
      // (e.g. meta.getName(person)) can resolve variables from outer scope.
      rightScope = Scope(leftResult, constants: scope.constants, parent: scope);
    } else {
      error = RuntimeError.fromParseTree(
        'Left side of member access did not resolve to a Scope or Object',
        node.children[0],
      );
      return TickResult.completed;
    }

    if (_rightNode == null) {
      var rightChild = node.children[1];

      // Right side can be either an identifier or any other expression (like a call)
      // For identifiers, we use the rightScope to look up the member
      // For other expressions, we execute them in the rightScope
      if (rightChild.symbol == Symbols.identifier) {
        _rightNode = IdentifierExecutionNode(
          rightChild,
          thread: thread,
          scope: rightScope,
        );
      } else {
        // For non-identifier expressions (like method calls), create execution node with rightScope
        _rightNode = Engine.createExecutionNode(rightChild, thread, rightScope);
        if (_rightNode == null) {
          error = RuntimeError.fromParseTree(
            'Failed to create execution node for right side of member access',
            rightChild,
          );
          return TickResult.completed;
        }
      }
      return TickResult.delegated;
    }

    result = _rightNode!.result;
    error ??= _rightNode!.error;
    return TickResult.completed;
  }

  void assign(dynamic value) {
    // Get the Object from the left side
    var leftResult = _leftNode!.result;
    Object obj;

    if (leftResult is Scope) {
      obj = leftResult.members;
    } else if (leftResult is Object) {
      obj = leftResult;
    } else {
      throw RuntimeError.fromParseTree(
        'Cannot assign to member of non-Object type',
        node,
      );
    }

    // Get the field identifier from the right side
    var identifierNode = node.children[1];
    String fieldName = identifierNode.tokens.first.lexeme.toUpperCase();
    int fieldId = _identifiers!.include(fieldName);

    // Set the field value
    obj.setVariable(fieldId, value);
  }
}
