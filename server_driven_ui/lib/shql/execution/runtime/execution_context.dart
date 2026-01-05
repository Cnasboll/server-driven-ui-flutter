import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/lambdas/user_function_execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime/runtime.dart';

class ExecutionContext {
  late final Runtime runtime;
  late final Thread mainThread;
  late final Map<int, Thread> threads;
  int nextThreadId = 1;
  final String? sourceCode;

  ExecutionContext({required this.runtime, this.sourceCode}) {
    mainThread = Thread(id: 0);
    threads = {0: mainThread};
  }

  Future<bool> tick([CancellationToken? cancellationToken]) async {
    // Never remove main thread even if "idle"
    threads.removeWhere((key, thread) => key > 0 && thread.isIdle);

    if (cancellationToken != null && await cancellationToken.check()) {
      return true;
    }

    var activeThreads = threads.values
        .where((thread) => !thread.isIdle)
        .toList();

    if (activeThreads.isEmpty) {
      return true;
    }

    var tickFutures = activeThreads
        .map((thread) => thread.tick(this, cancellationToken))
        .toList();

    await Future.any(tickFutures);

    // If we get here, at least one thread has completed a tick.

    if (!threads.values.any((thread) => !thread.isIdle)) {
      // All threads are now idle.
      return true;
    }

    // The overall execution is not yet complete.
    return false;
  }

  Future<Thread> startThread(ExecutionNode caller, dynamic userFunction) async {
    var thread = Thread(id: nextThreadId++);
    threads[thread.id] = thread;

    UserFunctionExecutionNode(
      userFunction,
      [],
      thread: thread,
      scope: caller.scope,
    );
    return thread;
  }
}
