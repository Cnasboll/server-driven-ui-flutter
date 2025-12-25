import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/engine/engine.dart';
import 'package:shql/execution/assignment_execution_node.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/identifier_exeuction_node.dart';
import 'package:shql/execution/lazy_execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';
import 'package:shql/execution/runtime_error.dart';
import 'package:shql/execution/set_variable_execution_node.dart';
import 'package:shql/parser/parse_tree.dart';
import 'package:shql/tokenizer/token.dart';

class ForLoopExecutionNode extends LazyExecutionNode {
  ForLoopExecutionNode(
    super.node, {
    required super.thread,
    required super.scope,
  });

  AssignmentExecutionNode? _initializationNode;
  IdentifierExecutionNode? _loopVariablenode;
  ExecutionNode? _targetNode;
  ExecutionNode? _stepNode;
  ExecutionNode? _bodyNode;

  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) async {
    if (_initializationNode == null) {
      var (initializationNode, initError) = _createInitializationNode(
        executionContext,
      );
      if (initError != null) {
        error = initError;
        return TickResult.completed;
      }
      _initializationNode = initializationNode;
      return TickResult.delegated;
    }

    if (_bodyNode == null) {
      result ??= _initializationNode!.result;
      error ??= _initializationNode!.error;
      _bodyNode = Engine.createExecutionNode(bodyParseTree, thread, scope);
      return TickResult.delegated;
    }

    if (_targetNode == null) {
      result = _bodyNode!.result;
      error ??= _bodyNode!.error;
      _targetNode = Engine.createExecutionNode(targetParseTree, thread, scope);
      return TickResult.delegated;
    }

    if (_loopVariablenode == null) {
      _loopVariablenode = IdentifierExecutionNode(
        identifierParseTree,
        thread: thread,
        scope: scope,
      );
      return TickResult.delegated;
    }

    var initialIteratorValue = _initializationNode!.result;
    var currentIteratorValue = _loopVariablenode!.result;
    var targetValue = _targetNode!.result;

    bool iteratingForward = targetValue >= initialIteratorValue;

    if (_stepNode == null && hasStepNode) {
      _stepNode = Engine.createExecutionNode(stepParseTree, thread, scope);
      return TickResult.delegated;
    }

    var increment = _stepNode != null
        ? _stepNode!.result
        : (iteratingForward ? 1 : -1);

    var newIteratorValue = currentIteratorValue + increment;

    bool passingTarget = iteratingForward
        ? newIteratorValue > targetValue
        : newIteratorValue < targetValue;
    if (passingTarget) {
      return _complete(executionContext);
    }

    SetVariableExecutionNode(
      identifierParseTree,
      newIteratorValue,
      thread: thread,
      scope: scope,
    );

    // Here we actually don't return TickResult.delegated nor store the SetVariableExecutionNode,
    // because we want to set the variable immediately
    // and restart the loop

    _reset();
    return TickResult.iterated;
  }

  void _reset() {
    _loopVariablenode = null;
    _targetNode = null;
    _bodyNode = null;
    _stepNode = null;
  }

  TickResult _complete(ExecutionContext executionContext) {
    return TickResult.completed;
  }

  (AssignmentExecutionNode?, RuntimeError?) _createInitializationNode(
    ExecutionContext executionContext,
  ) {
    if (initializationParseTree.symbol != Symbols.assignment) {
      return (
        null,
        RuntimeError.fromParseTree(
          'For loop initialization must be an assignment.',
          initializationParseTree,
        ),
      );
    }

    var initializationNode = Engine.tryCreateAssignmentExecutionNode(
      initializationParseTree,
      thread,
      scope,
    );
    if (initializationNode == null) {
      return (
        null,
        RuntimeError.fromParseTree(
          'Could not create assignment execution node.',
          initializationParseTree,
        ),
      );
    }
    return (initializationNode, null);
  }

  @override
  bool get isLoop => true;

  @override
  void continueLoop() {
    _reset();
  }

  ParseTree get initializationParseTree => node.children[0];
  ParseTree get identifierParseTree => node.children[0].children[0];
  ParseTree get bodyParseTree => node.children[1];
  ParseTree get targetParseTree => node.children[2];
  bool get hasStepNode => node.children.length > 3;
  ParseTree get stepParseTree => node.children[3];
}
