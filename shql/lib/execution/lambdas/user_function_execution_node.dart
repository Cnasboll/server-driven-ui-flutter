import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/engine/engine.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';
import 'package:shql/execution/runtime/runtime.dart';

class UserFunctionExecutionNode extends ExecutionNode {
  UserFunctionExecutionNode(
    this.userFunction,
    this.arguments, {
    required super.thread,
    required super.scope,
  });

  final UserFunction userFunction;
  final List<dynamic> arguments;
  ExecutionNode? body;

  @override
  Future<TickResult> doTick(
    ExecutionContext executionContext,
    CancellationToken? cancellationToken,
  ) async {
    if (returnTarget == null) {
      var childScope = Scope(
        Object(),
        constants: userFunction.scope.constants,
        parent: userFunction.scope,
      );
      // Assign argument values to identifiers
      var argumentIdentifiers = userFunction.argumentIdentifiers;
      for (int i = 0; i < argumentIdentifiers.length; i++) {
        var argument = arguments[i];
        if (argument is UserFunction) {
          // Define user function in child scope, in members directly so it is definetely shadowed
          childScope.members.defineUserFunction(
            argumentIdentifiers[i],
            argument,
          );
        } else {
          // Define variable child scope, in members directly so it is definetely shadowed
          childScope.members.setVariable(argumentIdentifiers[i], argument);
        }
      }
      var (r, error) = thread.pushReturnTarget();
      if (error != null) {
        this.error = error;
        return TickResult.completed;
      }
      returnTarget = r;
      body = Engine.createExecutionNode(userFunction.body, thread, childScope);
      return TickResult.delegated;
    }

    error ??= body!.error;
    if (returnTarget!.hasReturnValue) {
      result ??= returnTarget!.returnValue;
    } else {
      result ??= body!.result;
    }

    return TickResult.completed;
  }
}
