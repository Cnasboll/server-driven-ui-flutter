import 'dart:core';

import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/execution/apriori_execution_node.dart';
import 'package:shql/execution/lambdas/call_execution_node.dart';
import 'package:shql/execution/operators/artithmetic/addition_execution_node.dart';
import 'package:shql/execution/operators/artithmetic/division_execution_node.dart';
import 'package:shql/execution/operators/artithmetic/modulus_execution_node.dart';
import 'package:shql/execution/operators/artithmetic/multiplication_execution_node.dart';
import 'package:shql/execution/operators/artithmetic/subtraction_execution_node.dart';
import 'package:shql/execution/operators/artithmetic/unary_minus_execution_node.dart';
import 'package:shql/execution/assignment_execution_node.dart';
import 'package:shql/execution/operators/boolean/and_execution_node.dart';
import 'package:shql/execution/operators/boolean/not_execution_node.dart';
import 'package:shql/execution/operators/boolean/or_execution_node.dart';
import 'package:shql/execution/operators/boolean/xor_execution_node.dart';
import 'package:shql/execution/break_statement_execution_node.dart';
import 'package:shql/execution/compound_statement_execution_node.dart';
import 'package:shql/execution/constant_node.dart';
import 'package:shql/execution/continue_statement_execution_node.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/operators/artithmetic/exponentiation_execution_node.dart';
import 'package:shql/execution/for_loop_execution_node.dart';
import 'package:shql/execution/identifier_exeuction_node.dart';
import 'package:shql/execution/if_statement_execution_node.dart';
import 'package:shql/execution/lambdas/lambda_expression_execution_node.dart';
import 'package:shql/execution/list_literal_node.dart';
import 'package:shql/execution/map_literal_node.dart';
import 'package:shql/execution/object_literal_node.dart';
import 'package:shql/execution/operators/objects/colon_execution_node.dart';
import 'package:shql/execution/operators/objects/member_access_execution_node.dart';
import 'package:shql/execution/operators/pattern/in_execution_node.dart';
import 'package:shql/execution/operators/pattern/match_execution_node.dart';
import 'package:shql/execution/operators/pattern/not_match_execution_node.dart';
import 'package:shql/execution/program_execution_node.dart';
import 'package:shql/execution/operators/relational/equality_execution_node.dart';
import 'package:shql/execution/operators/relational/greater_than_execution_node.dart';
import 'package:shql/execution/operators/relational/greater_than_or_equal_execution_node.dart';
import 'package:shql/execution/operators/relational/less_than_execution_node.dart';
import 'package:shql/execution/operators/relational/less_than_or_equal_execution_node.dart';
import 'package:shql/execution/operators/relational/not_equality_execution_node.dart';
import 'package:shql/execution/repeat_until_loop_execution_node.dart';
import 'package:shql/execution/return_statement_execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/execution/tuple_literal_node.dart';
import 'package:shql/execution/while_loop_execution_node.dart';
import 'package:shql/parser/constants_set.dart';
import 'package:shql/execution/runtime_error.dart';
import 'package:shql/parser/parse_tree.dart';
import 'package:shql/parser/parser.dart';
import 'package:shql/tokenizer/token.dart';

class RuntimeException implements Exception {
  final RuntimeError error;

  RuntimeException(this.error);

  @override
  String toString() => 'RuntimeException: ${error.formattedMessage}';
}

class Engine {
  static Future<dynamic> execute(
    String code, {
    Runtime? runtime,
    ConstantsSet? constantsSet,
    CancellationToken? cancellationToken,
    Map<String, dynamic>? boundValues,
  }) async {
    // print('Executing SHQL™ code:\n$code');
    constantsSet ??= Runtime.prepareConstantsSet();
    runtime ??= Runtime.prepareRuntime(constantsSet);

    var program = Parser.parse(code, constantsSet, sourceCode: code);

    return await _execute(
      program,
      runtime,
      cancellationToken,
      boundValues: boundValues,
      sourceCode: code,
    );
  }

  static Future<dynamic> evalExpr(
    String expression, {
    Runtime? runtime,
    ConstantsSet? constantsSet,
  }) async {
    // print('Evaluating SHQL™ expression:\n$expression');
    constantsSet ??= Runtime.prepareConstantsSet();
    runtime ??= Runtime.prepareRuntime(constantsSet);

    var program = Parser.parse(
      expression,
      constantsSet,
      sourceCode: expression,
    );

    var result = await _evaluate(program, runtime, null, expression);

    if (result.$2 == false) {
      return null;
    }
    return result.$1;
  }

  static Scope getScope(Runtime runtime, Map<String, dynamic>? boundValues) {
    var scope = runtime.globalScope;
    if (boundValues != null) {
      scope = Scope(Object(), constants: scope.constants, parent: scope);
      for (var entry in boundValues.entries) {
        scope.members.setVariable(
          runtime.identifiers.include(entry.key.toUpperCase()),
          entry.value,
        );
      }
    }
    return scope;
  }

  /// Execute a pre-parsed [ParseTree] directly, skipping the parse step.
  /// Use this for hot loops where the same expression is evaluated repeatedly
  /// with different [boundValues].
  static Future<dynamic> executeParsed(
    ParseTree parseTree, {
    required Runtime runtime,
    CancellationToken? cancellationToken,
    Map<String, dynamic>? boundValues,
  }) {
    return _execute(parseTree, runtime, cancellationToken, boundValues: boundValues);
  }

  static Future<dynamic> _execute(
    ParseTree parseTree,
    Runtime runtime,
    CancellationToken? cancellationToken, {
    Map<String, dynamic>? boundValues,
    String? sourceCode,
  }) async {
    var executionContext = ExecutionContext(runtime: runtime);
    Scope scope = getScope(runtime, boundValues);
    var executionNode = createExecutionNode(
      parseTree,
      executionContext.mainThread,
      scope,
    );
    if (executionNode == null) {
      throw RuntimeException(RuntimeError('Failed to create execution node.'));
    }

    var ticksSinceYield = 0;
    while ((cancellationToken == null || !cancellationToken.isCancelled) &&
        !await executionContext.tick(cancellationToken)) {
      if (++ticksSinceYield >= 1000) {
        await Future.delayed(Duration.zero);
        ticksSinceYield = 0;
      }
    }

    if (executionContext.mainThread.error != null) {
      throw RuntimeException(executionContext.mainThread.error!);
    }

    return executionContext.mainThread.result;
  }

  static Future<(dynamic, bool)> _evaluate(
    ParseTree parseTree,
    Runtime runtime, [
    Map<String, dynamic>? boundValues,
    String? sourceCode,
  ]) async {
    var executionContext = ExecutionContext(runtime: runtime);
    Scope scope = getScope(runtime, boundValues);
    var executionNode = createExecutionNode(
      parseTree,
      executionContext.mainThread,
      scope,
    );
    if (executionNode == null) {
      throw RuntimeException(RuntimeError('Failed to create execution node.'));
    }

    if (!await executionContext.tick()) {
      return (null, false);
    }

    if (executionContext.mainThread.error != null) {
      throw RuntimeException(executionContext.mainThread.error!);
    }

    return (executionContext.mainThread.result, true);
  }

  static ExecutionNode? createExecutionNode(
    ParseTree parseTree,
    Thread thread,
    Scope scope,
  ) {
    if (parseTree.symbol == Symbols.nullLiteral) {
      return AprioriExecutionNode(null, thread: thread, scope: scope);
    }

    ExecutionNode? executionNode = tryCreateProgramExecutionNode(
      parseTree,
      thread,
      scope,
    );
    if (executionNode != null) {
      return executionNode;
    }

    executionNode = tryCreateTerminalExecutionNode(parseTree, thread, scope);
    if (executionNode != null) {
      return executionNode;
    }

    executionNode = tryCreateUnaryExecutionNode(parseTree, thread, scope);
    if (executionNode != null) {
      return executionNode;
    }

    executionNode = tryCreateIfStatementExecutionNode(parseTree, thread, scope);
    if (executionNode != null) {
      return executionNode;
    }

    executionNode = tryCreateWhileLoopExecutionNode(parseTree, thread, scope);
    if (executionNode != null) {
      return executionNode;
    }

    executionNode = tryCreateRepeatUntilLoopExecutionNode(
      parseTree,
      thread,
      scope,
    );
    if (executionNode != null) {
      return executionNode;
    }

    executionNode = tryCreateForLoopExecutionNode(parseTree, thread, scope);
    if (executionNode != null) {
      return executionNode;
    }

    executionNode = tryCreateBreakStatementExecutionNode(
      parseTree,
      thread,
      scope,
    );
    if (executionNode != null) {
      return executionNode;
    }

    executionNode = tryCreateContinueStatementExecutionNode(
      parseTree,
      thread,
      scope,
    );
    if (executionNode != null) {
      return executionNode;
    }

    executionNode = tryCreateReturnStatementExecutionNode(
      parseTree,
      thread,
      scope,
    );
    if (executionNode != null) {
      return executionNode;
    }

    executionNode = tryCreateCompoundStatementExecutionNode(
      parseTree,
      thread,
      scope,
    );
    if (executionNode != null) {
      return executionNode;
    }

    if (parseTree.children.length < 2) {
      return AprioriExecutionNode(double.nan, thread: thread, scope: scope);
    }

    if (parseTree.symbol == Symbols.memberAccess) {
      return MemberAccessExecutionNode(parseTree, thread: thread, scope: scope);
    }
    executionNode = tryCreateCallExecutionNode(parseTree, thread, scope);

    if (executionNode != null) {
      return executionNode;
    }

    executionNode = tryCreateNameValuePairExecutionNode(
      parseTree,
      thread,
      scope,
    );

    if (executionNode != null) {
      return executionNode;
    }

    executionNode = tryCreateLambdaExpressionExecutionNode(
      parseTree,
      thread,
      scope,
    );
    if (executionNode != null) {
      return executionNode;
    }

    executionNode = tryCreateAssignmentExecutionNode(parseTree, thread, scope);
    if (executionNode != null) {
      return executionNode;
    }

    return createBinaryOperatorExecutionNode(parseTree, thread, scope);
  }

  static ExecutionNode? createBinaryOperatorExecutionNode(
    ParseTree parseTree,
    Thread thread,
    Scope scope,
  ) {
    var lhs = parseTree.children[0];
    var rhs = parseTree.children[1];
    switch (parseTree.symbol) {
      case Symbols.inOp:
        return InExecutionNode(lhs, rhs, thread: thread, scope: scope);
      case Symbols.pow:
        return ExponentiationExecutionNode(
          lhs,
          rhs,
          thread: thread,
          scope: scope,
        );
      case Symbols.mul:
        return MultiplicationExecutionNode(
          lhs,
          rhs,
          thread: thread,
          scope: scope,
        );
      case Symbols.div:
        return DivisionExecutionNode(lhs, rhs, thread: thread, scope: scope);
      case Symbols.mod:
        return ModulusExecutionNode(lhs, rhs, thread: thread, scope: scope);
      case Symbols.add:
        return AdditionExecutionNode(lhs, rhs, thread: thread, scope: scope);
      case Symbols.sub:
        return SubtractionExecutionNode(lhs, rhs, thread: thread, scope: scope);
      case Symbols.lt:
        return LessThanExecutionNode(lhs, rhs, thread: thread, scope: scope);
      case Symbols.ltEq:
        return LessThanOrEqualExecutionNode(
          lhs,
          rhs,
          thread: thread,
          scope: scope,
        );
      case Symbols.gt:
        return GreaterThanExecutionNode(lhs, rhs, thread: thread, scope: scope);
      case Symbols.gtEq:
        return GreaterThanOrEqualExecutionNode(
          lhs,
          rhs,
          thread: thread,
          scope: scope,
        );
      case Symbols.eq:
        return EqualityExecutionNode(lhs, rhs, thread: thread, scope: scope);
      case Symbols.neq:
        return NotEqualityExecutionNode(lhs, rhs, thread: thread, scope: scope);
      case Symbols.match:
        return MatchExecutionNode(lhs, rhs, thread: thread, scope: scope);
      case Symbols.notMatch:
        return NotMatchExecutionNode(lhs, rhs, thread: thread, scope: scope);
      case Symbols.and:
        return AndExecutionNode(lhs, rhs, thread: thread, scope: scope);
      case Symbols.or:
        return OrExecutionNode(lhs, rhs, thread: thread, scope: scope);
      case Symbols.xor:
        return XorExecutionNode(lhs, rhs, thread: thread, scope: scope);
      default:
        return null;
    }
  }

  static ProgramExecutionNode? tryCreateProgramExecutionNode(
    ParseTree parseTree,
    Thread thread,
    Scope scope,
  ) {
    if (parseTree.symbol != Symbols.program) {
      return null;
    }
    return ProgramExecutionNode(parseTree, thread: thread, scope: scope);
  }

  static ExecutionNode? tryCreateTerminalExecutionNode(
    ParseTree parseTree,
    Thread thread,
    Scope scope,
  ) {
    switch (parseTree.symbol) {
      case Symbols.list:
        return ListLiteralNode(parseTree, thread: thread, scope: scope);
      case Symbols.tuple:
        return TupleLiteralNode(parseTree, thread: thread, scope: scope);
      case Symbols.map:
        return MapLiteralNode(parseTree, thread: thread, scope: scope);
      case Symbols.objectLiteral:
        return ObjectLiteralNode(parseTree, thread: thread, scope: scope);
      case Symbols.floatLiteral:
        return ConstantNode<double>(parseTree, thread: thread, scope: scope);
      case Symbols.integerLiteral:
        return ConstantNode<int>(parseTree, thread: thread, scope: scope);
      case Symbols.stringLiteral:
        return ConstantNode<String>(parseTree, thread: thread, scope: scope);
      case Symbols.identifier:
        return IdentifierExecutionNode(parseTree, thread: thread, scope: scope);
      default:
        return null;
    }
  }

  static bool isUnary(Symbols symbol) {
    return [
      Symbols.unaryMinus,
      Symbols.unaryPlus,
      Symbols.not,
    ].contains(symbol);
  }

  static ExecutionNode? tryCreateUnaryExecutionNode(
    ParseTree parseTree,
    Thread thread,
    Scope scope,
  ) {
    if (!isUnary(parseTree.symbol)) {
      return null;
    }

    switch (parseTree.symbol) {
      case Symbols.unaryMinus:
        // Unary minus
        return UnaryMinusExecutionNode(
          parseTree.children[0],
          thread: thread,
          scope: scope,
        );
      case Symbols.unaryPlus:
        // Unary plus evalautes to first child
        return Engine.createExecutionNode(parseTree.children[0], thread, scope);
      case Symbols.not:
        return NotExecutionNode(
          parseTree.children[0],
          thread: thread,
          scope: scope,
        );
      default:
        return null;
    }
  }

  static IfStatementExecutionNode? tryCreateIfStatementExecutionNode(
    ParseTree parseTree,
    Thread thread,
    Scope scope,
  ) {
    if (parseTree.symbol != Symbols.ifStatement) {
      return null;
    }
    return IfStatementExecutionNode(parseTree, thread: thread, scope: scope);
  }

  static WhileLoopExecutionNode? tryCreateWhileLoopExecutionNode(
    ParseTree parseTree,
    Thread thread,
    Scope scope,
  ) {
    if (parseTree.symbol != Symbols.whileLoop) {
      return null;
    }
    return WhileLoopExecutionNode(parseTree, thread: thread, scope: scope);
  }

  static RepeatUntilLoopExecutionNode? tryCreateRepeatUntilLoopExecutionNode(
    ParseTree parseTree,
    Thread thread,
    Scope scope,
  ) {
    if (parseTree.symbol != Symbols.repeatUntilLoop) {
      return null;
    }
    return RepeatUntilLoopExecutionNode(
      parseTree,
      thread: thread,
      scope: scope,
    );
  }

  static ForLoopExecutionNode? tryCreateForLoopExecutionNode(
    ParseTree parseTree,
    Thread thread,
    Scope scope,
  ) {
    if (parseTree.symbol != Symbols.forLoop) {
      return null;
    }
    return ForLoopExecutionNode(parseTree, thread: thread, scope: scope);
  }

  static BreakStatementExecutionNode? tryCreateBreakStatementExecutionNode(
    ParseTree parseTree,
    Thread thread,
    Scope scope,
  ) {
    if (parseTree.symbol != Symbols.breakStatement) {
      return null;
    }
    return BreakStatementExecutionNode(thread: thread, scope: scope);
  }

  static ContinueStatementExecutionNode?
  tryCreateContinueStatementExecutionNode(
    ParseTree parseTree,
    Thread thread,
    Scope scope,
  ) {
    if (parseTree.symbol != Symbols.continueStatement) {
      return null;
    }
    return ContinueStatementExecutionNode(thread: thread, scope: scope);
  }

  static ReturnStatementExecutionNode? tryCreateReturnStatementExecutionNode(
    ParseTree parseTree,
    Thread thread,
    Scope scope,
  ) {
    if (parseTree.symbol != Symbols.returnStatement) {
      return null;
    }
    return ReturnStatementExecutionNode(
      parseTree,
      thread: thread,
      scope: scope,
    );
  }

  static CompoundStatementExecutionNode?
  tryCreateCompoundStatementExecutionNode(
    ParseTree parseTree,
    Thread thread,
    Scope scope,
  ) {
    if (parseTree.symbol != Symbols.compoundStatement) {
      return null;
    }
    return CompoundStatementExecutionNode(
      parseTree,
      thread: thread,
      scope: scope,
    );
  }

  static CallExecutionNode? tryCreateCallExecutionNode(
    ParseTree parseTree,
    Thread thread,
    Scope scope,
  ) {
    if (parseTree.symbol != Symbols.call) {
      return null;
    }
    return CallExecutionNode(parseTree, thread: thread, scope: scope);
  }

  static NameValuePairExecutionNode? tryCreateNameValuePairExecutionNode(
    ParseTree parseTree,
    Thread thread,
    Scope scope,
  ) {
    if (parseTree.symbol != Symbols.colon) {
      return null;
    }
    return NameValuePairExecutionNode(
      parseTree.children[0],
      parseTree.children[1],
      thread: thread,
      scope: scope,
    );
  }

  static LambdaExpressionExecutionNode? tryCreateLambdaExpressionExecutionNode(
    ParseTree parseTree,
    Thread thread,
    Scope scope,
  ) {
    if (parseTree.symbol != Symbols.lambdaExpression) {
      return null;
    }
    return LambdaExpressionExecutionNode(
      "anonymous",
      parseTree,
      thread: thread,
      scope: scope,
    );
  }

  static AssignmentExecutionNode? tryCreateAssignmentExecutionNode(
    ParseTree parseTree,
    Thread thread,
    Scope scope,
  ) {
    if (parseTree.symbol != Symbols.assignment) {
      return null;
    }
    return AssignmentExecutionNode(parseTree, thread: thread, scope: scope);
  }
}
