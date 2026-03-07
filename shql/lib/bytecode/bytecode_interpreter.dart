/// Stack-based interpreter for the SHQL™ bytecode VM.
///
/// The execution model uses an explicit call stack of [BytecodeFrame]s inside
/// each [BytecodeThread], replacing the old recursive-async approach.
/// This makes preemption trivial: [BytecodeInterpreter.tick] executes at most
/// [quantum] instructions per thread, so [BytecodeExecutionContext] can
/// interleave multiple threads in a cooperative round-robin.
///
/// Variables are stored in the same [Scope] / [Object] chain used by the
/// existing execution-node runtime, and identifier names are interned via
/// [Runtime.identifiers] so that bytecode and traditional SHQL™ programs
/// share the same identifier space.
library;

import 'package:shql/bytecode/bytecode.dart';
import 'package:shql/execution/runtime/runtime.dart';

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

class BytecodeRuntimeError implements Exception {
  final String message;

  BytecodeRuntimeError(this.message);

  @override
  String toString() => 'BytecodeRuntimeError: $message';
}

// ---------------------------------------------------------------------------
// Callable wrappers
// ---------------------------------------------------------------------------

/// A compiled closure pushed onto the value stack by [Opcode.makeClosure] or
/// [Opcode.pushConst] with a [ChunkRef] constant.
class BytecodeCallable {
  final BytecodeChunk chunk;
  final Scope capturedScope;

  BytecodeCallable(this.chunk, this.capturedScope);

  @override
  String toString() => 'BytecodeCallable(${chunk.name})';
}

/// A native Dart function registered via [BytecodeInterpreter.registerNative].
class _NativeCallable {
  final dynamic Function(List<dynamic> args) fn;

  _NativeCallable(this.fn);
}

// ---------------------------------------------------------------------------
// Execution frame and thread
// ---------------------------------------------------------------------------

/// One activation record on a [BytecodeThread]'s call stack.
class BytecodeFrame {
  final BytecodeChunk chunk;
  int pc;
  final List<dynamic> stack;
  Scope scope; // mutable: push_scope / pop_scope update it in place

  BytecodeFrame({
    required this.chunk,
    required this.pc,
    required this.stack,
    required this.scope,
  });
}

/// A cooperative thread in the bytecode VM.
///
/// Each thread owns an explicit call stack of [BytecodeFrame]s.
/// [BytecodeInterpreter.tick] advances the thread by at most [quantum]
/// instructions.  When [isRunning] becomes false the thread has either
/// completed ([result] is set) or faulted ([error] is set).
class BytecodeThread {
  final List<BytecodeFrame> callStack;
  dynamic result;
  BytecodeRuntimeError? error;

  BytecodeThread({required BytecodeFrame initialFrame})
      : callStack = [initialFrame];

  bool get isRunning => callStack.isNotEmpty;
  BytecodeFrame get currentFrame => callStack.last;
}

// ---------------------------------------------------------------------------
// Interpreter
// ---------------------------------------------------------------------------

class BytecodeInterpreter {
  final BytecodeProgram program;
  final Runtime runtime;
  final Map<int, dynamic Function(List<dynamic>)> _nativeFunctions = {};

  BytecodeInterpreter(this.program, this.runtime);

  /// Register a native Dart function callable from bytecode via [Opcode.call].
  /// [name] is case-insensitive (uppercased to match SHQL™ identifier semantics).
  void registerNative(String name, dynamic Function(List<dynamic> args) fn) {
    _nativeFunctions[runtime.identifiers.include(name.toUpperCase())] = fn;
  }

  /// Create a new [BytecodeThread] ready to run [chunkName] with [args].
  BytecodeThread createThread(
    String chunkName, [
    List<dynamic> args = const [],
  ]) {
    return BytecodeThread(
      initialFrame: _makeFrame(program[chunkName], args, runtime.globalScope),
    );
  }

  /// Convenience: run [chunkName] to completion on a single thread.
  /// Backward-compatible with the old async API; pure computation never yields.
  Future<dynamic> execute([
    String chunkName = 'main',
    List<dynamic> args = const [],
  ]) {
    final thread = createThread(chunkName, args);
    while (thread.isRunning) {
      _tickOne(thread);
    }
    if (thread.error != null) throw thread.error!;
    return Future.value(thread.result);
  }

  /// Execute at most [quantum] instructions of [thread].
  void tick(BytecodeThread thread, [int quantum = 100]) {
    var remaining = quantum;
    while (thread.isRunning && remaining > 0) {
      _tickOne(thread);
      remaining--;
    }
  }

  // ---- Frame construction --------------------------------------------------

  BytecodeFrame _makeFrame(
    BytecodeChunk chunk,
    List<dynamic> args,
    Scope parentScope,
  ) {
    final scope = Scope(Object(), parent: parentScope);
    for (var i = 0; i < chunk.params.length && i < args.length; i++) {
      final id = runtime.identifiers.include(chunk.params[i].toUpperCase());
      scope.setVariable(id, args[i]);
    }
    return BytecodeFrame(chunk: chunk, pc: 0, stack: [], scope: scope);
  }

  // ---- Single-instruction dispatch ----------------------------------------

  void _tickOne(BytecodeThread thread) {
    try {
      _dispatch(thread);
    } catch (e) {
      thread.error =
          e is BytecodeRuntimeError ? e : BytecodeRuntimeError('$e');
      thread.callStack.clear(); // terminate thread on error
    }
  }

  void _dispatch(BytecodeThread thread) {
    final frame = thread.currentFrame;

    // Implicit return past end of chunk
    if (frame.pc >= frame.chunk.code.length) {
      _doRet(thread, frame.stack.isEmpty ? null : frame.stack.last);
      return;
    }

    final instr = frame.chunk.code[frame.pc++];
    final stack = frame.stack;

    switch (instr.op) {
      // ---- Stack / variables -----------------------------------------------

      case Opcode.pushConst:
        final c = frame.chunk.constants[instr.operand];
        stack.add(
          c is ChunkRef ? BytecodeCallable(program[c.name], frame.scope) : c,
        );

      case Opcode.loadVar:
        final id = _id(frame.chunk, instr.operand);
        final (raw, _, _) = frame.scope.resolveIdentifier(id);
        if (raw != null) {
          stack.add(_unwrap(raw));
        } else {
          final native = _nativeFunctions[id];
          stack.add(native != null ? _NativeCallable(native) : null);
        }

      case Opcode.storeVar:
        final id = _id(frame.chunk, instr.operand);
        frame.scope.setVariable(id, stack.removeLast());

      case Opcode.pop:
        stack.removeLast();

      // ---- Arithmetic ------------------------------------------------------

      case Opcode.add:
        final b = stack.removeLast(), a = stack.removeLast();
        stack.add(a + b);

      case Opcode.sub:
        final b = stack.removeLast(), a = stack.removeLast();
        stack.add(a - b);

      case Opcode.mul:
        final b = stack.removeLast(), a = stack.removeLast();
        stack.add(a * b);

      case Opcode.div:
        final b = stack.removeLast(), a = stack.removeLast();
        stack.add(a / b);

      case Opcode.mod:
        final b = stack.removeLast(), a = stack.removeLast();
        stack.add(a % b);

      case Opcode.neg:
        stack.add(-(stack.removeLast() as num));

      // ---- Comparison ------------------------------------------------------

      case Opcode.cmpEq:
        final b = stack.removeLast(), a = stack.removeLast();
        stack.add(a == b);

      case Opcode.cmpNeq:
        final b = stack.removeLast(), a = stack.removeLast();
        stack.add(a != b);

      case Opcode.cmpLt:
        final b = stack.removeLast(), a = stack.removeLast();
        stack.add((a as num) < (b as num));

      case Opcode.cmpLte:
        final b = stack.removeLast(), a = stack.removeLast();
        stack.add((a as num) <= (b as num));

      case Opcode.cmpGt:
        final b = stack.removeLast(), a = stack.removeLast();
        stack.add((a as num) > (b as num));

      case Opcode.cmpGte:
        final b = stack.removeLast(), a = stack.removeLast();
        stack.add((a as num) >= (b as num));

      // ---- Logic -----------------------------------------------------------

      case Opcode.logAnd:
        final b = stack.removeLast(), a = stack.removeLast();
        stack.add(_truthy(a) && _truthy(b));

      case Opcode.logOr:
        final b = stack.removeLast(), a = stack.removeLast();
        stack.add(_truthy(a) || _truthy(b));

      case Opcode.logNot:
        stack.add(!_truthy(stack.removeLast()));

      // ---- Control flow ----------------------------------------------------

      case Opcode.jump:
        frame.pc = instr.operand;

      case Opcode.jumpFalse:
        if (!_truthy(stack.removeLast())) frame.pc = instr.operand;

      case Opcode.jumpTrue:
        if (_truthy(stack.removeLast())) frame.pc = instr.operand;

      // ---- Scope -----------------------------------------------------------

      case Opcode.pushScope:
        frame.scope = Scope(Object(), parent: frame.scope);

      case Opcode.popScope:
        frame.scope = frame.scope.parent ?? frame.scope;

      // ---- Functions / closures -------------------------------------------

      case Opcode.call:
        final argCount = instr.operand;
        final callArgs = List<dynamic>.filled(argCount, null);
        for (var i = argCount - 1; i >= 0; i--) {
          callArgs[i] = stack.removeLast();
        }
        final callable = stack.removeLast();
        if (callable is BytecodeCallable) {
          // Push a new frame — no recursion, no Future allocation
          thread.callStack.add(
            _makeFrame(callable.chunk, callArgs, callable.capturedScope),
          );
        } else if (callable is _NativeCallable) {
          stack.add(callable.fn(callArgs));
        } else {
          throw BytecodeRuntimeError('Cannot call $callable');
        }

      case Opcode.makeClosure:
        final ref = frame.chunk.constants[instr.operand];
        final name = ref is ChunkRef ? ref.name : ref as String;
        stack.add(BytecodeCallable(program[name], frame.scope));

      case Opcode.ret:
        _doRet(thread, stack.isEmpty ? null : stack.removeLast());

      // ---- Object / list access -------------------------------------------

      case Opcode.getMember:
        final id = _id(frame.chunk, instr.operand);
        final obj = stack.removeLast();
        if (obj is Object) {
          stack.add(_unwrap(obj.resolveIdentifier(id)));
        } else {
          throw BytecodeRuntimeError(
            'get_member: expected SHQL Object, got $obj',
          );
        }

      case Opcode.setMember:
        final id = _id(frame.chunk, instr.operand);
        final value = stack.removeLast();
        final obj = stack.removeLast();
        if (obj is Object) {
          obj.setVariable(id, value);
          stack.add(value);
        } else {
          throw BytecodeRuntimeError(
            'set_member: expected SHQL Object, got $obj',
          );
        }

      case Opcode.getIndex:
        final idx = stack.removeLast();
        final container = stack.removeLast();
        if (container is List) {
          stack.add(container[idx as int]);
        } else {
          throw BytecodeRuntimeError('get_index: cannot index $container');
        }

      case Opcode.setIndex:
        final value = stack.removeLast();
        final idx = stack.removeLast();
        final container = stack.removeLast();
        if (container is List) {
          container[idx as int] = value;
        } else {
          throw BytecodeRuntimeError('set_index: cannot index $container');
        }
        stack.add(value);

      case Opcode.makeList:
        final count = instr.operand;
        final items = List<dynamic>.filled(count, null);
        for (var i = count - 1; i >= 0; i--) {
          items[i] = stack.removeLast();
        }
        stack.add(items);

      case Opcode.makeObject:
        final pairCount = instr.operand;
        final obj = Object();
        final pairs = List<dynamic>.filled(pairCount * 2, null);
        for (var i = pairCount * 2 - 1; i >= 0; i--) {
          pairs[i] = stack.removeLast();
        }
        for (var i = 0; i < pairCount; i++) {
          final key = pairs[i * 2] as String;
          final id = runtime.identifiers.include(key.toUpperCase());
          obj.setVariable(id, pairs[i * 2 + 1]);
        }
        stack.add(obj);
    }
  }

  // ---- Helpers -------------------------------------------------------------

  void _doRet(BytecodeThread thread, dynamic value) {
    thread.callStack.removeLast();
    if (thread.callStack.isEmpty) {
      thread.result = value;
    } else {
      thread.callStack.last.stack.add(value); // push into caller's frame
    }
  }

  int _id(BytecodeChunk chunk, int index) {
    final name = chunk.constants[index] as String;
    return runtime.identifiers.include(name.toUpperCase());
  }

  static dynamic _unwrap(dynamic raw) => raw is Variable ? raw.value : raw;

  static bool _truthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.isNotEmpty;
    if (value is List) return value.isNotEmpty;
    return true;
  }
}
