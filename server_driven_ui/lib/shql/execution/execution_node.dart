import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/execution/runtime.dart';

enum TickResult { completed, iterated, delegated }

abstract class ExecutionNode {
  final Thread thread;
  final Scope scope;
  BreakTarget? breakTarget;
  ReturnTarget? returnTarget;

  ExecutionNode({required this.thread, required this.scope}) {
    thread.pushNode(this);
  }

  Future<TickResult> tick(
    Runtime runtime, [
    CancellationToken? cancellationToken,
  ]) async {
    if (isLoop) {
      breakTarget ??= thread.pushBreakTarget();
    }

    try {
      if (completed) {}
      if (await thread.check(cancellationToken)) {
        result = thread.result;
        error = thread.error;
        if (isLoop &&
            !await (breakTarget?.check(cancellationToken) ?? false) &&
            (breakTarget?.clearContinued() ?? false)) {
          continueLoop();
          return TickResult.iterated;
        }
        completed = true;
        thread.popNode();
        return TickResult.completed;
      }
      var tickResult = await doTick(runtime, cancellationToken);
      if (tickResult == TickResult.completed) {
        completed = true;
        thread.onExecutionNodeComplete(this);
      }
      return tickResult;
    } /* catch (e) {
      error = e.toString();
      completed = true;
      thread.onExecutionNodeComplete(this);
      return TickResult.completed;
    }*/ finally {
      if (completed) {
        if (isLoop) {
          thread.popBreakTarget();
        }
        if (returnTarget != null) {
          thread.popReturnTarget();
        }
      }
    }
  }

  Future<TickResult> doTick(
    Runtime runtime,
    CancellationToken? cancellationToken,
  );
  bool completed = false;
  String? error;
  dynamic result;
  dynamic getResult() {
    return result;
  }

  bool get isLoop => false;
  void continueLoop() {}
}
