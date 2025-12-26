import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/lambdas/user_function_execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime/runtime.dart';

class Execution {
  late final Runtime runtime;
  late final Thread mainThread;
  late final Map<int, Thread> threads;
  int nextThreadId = 1;

  Execution({required this.runtime}) {
    mainThread = Thread(id: 0);
    threads = {0: mainThread};
  }

  Future<bool> tick([CancellationToken? cancellationToken]) async {
    // Never remove main thread even if "idle"
    threads.removeWhere((key, thread) => key > 0 && thread.isIdle);
    var allTreads = threads.values.toList();
    for (var thread in allTreads) {
      if (thread.isIdle) {
        continue;
      }
      if (cancellationToken != null && await cancellationToken.check()) {
        return true;
      }

      if (await thread.tick(this, cancellationToken)) {
        if (cancellationToken != null && await cancellationToken.check()) {
          return true;
        }
        continue;
      }
    }
    return threads.values.every((thread) => thread.isIdle);
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
