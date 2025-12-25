import 'dart:async';

typedef Job = FutureOr<void> Function();

class JobQueue {
  final _controller = StreamController<Job>();
  late final Future<void> _done;

  JobQueue() {
    _done = _run();
  }

  void enqueue(Job job) => _controller.add(job);

  Future<void> close() => _controller.close();

  Future<void> join() => _done;

  Future<void> _run() async {
    await for (final job in _controller.stream) {
      await job();
    }
  }
}
