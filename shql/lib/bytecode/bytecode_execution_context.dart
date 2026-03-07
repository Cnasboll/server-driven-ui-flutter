/// Cooperative multi-threading for the SHQL™ bytecode VM.
///
/// [BytecodeExecutionContext] manages a pool of [BytecodeThread]s and ticks
/// them round-robin, giving each thread at most [quantum] instructions per
/// round — the same cooperative scheduling principle used by [ExecutionContext]
/// for [ExecutionNode] threads.
///
/// The [Runtime] is shared between all threads (and with any co-existing
/// tree-walking engine), so global scope variables written by one bytecode
/// thread are immediately visible to others.
library;

import 'package:shql/bytecode/bytecode_interpreter.dart';

class BytecodeExecutionContext {
  final BytecodeInterpreter interpreter;
  final List<BytecodeThread> _threads = [];

  BytecodeExecutionContext(this.interpreter);

  /// Spawn a new thread running [chunkName] with [args] and register it.
  BytecodeThread spawn(String chunkName, [List<dynamic> args = const []]) {
    final thread = interpreter.createThread(chunkName, args);
    _threads.add(thread);
    return thread;
  }

  bool get hasRunningThreads => _threads.any((t) => t.isRunning);

  /// Tick every running thread once, giving each [quantum] instructions.
  void tickAll([int quantum = 100]) {
    for (final t in _threads) {
      if (t.isRunning) interpreter.tick(t, quantum);
    }
    _threads.removeWhere((t) => !t.isRunning);
  }

  /// Run all threads to completion, yielding to the Dart event loop between
  /// rounds so that other async work (I/O, timers) can proceed.
  Future<void> runToCompletion([int quantum = 100]) async {
    while (hasRunningThreads) {
      tickAll(quantum);
      if (hasRunningThreads) await Future.delayed(Duration.zero);
    }
  }
}
