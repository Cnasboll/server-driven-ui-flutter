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

import 'dart:math' as math;

import 'package:shql/bytecode/bytecode.dart';
import 'package:shql/bytecode/bytecode_compiler.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/parser/constants_set.dart';
import 'package:shql/parser/parser.dart';

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

class BytecodeRuntimeError implements Exception {
  final String message;

  BytecodeRuntimeError(this.message);

  @override
  String toString() => 'BytecodeRuntimeError: $message';
}

/// Thrown internally by [BytecodeInterpreter.evalExpr] when a backward jump
/// is encountered.  Not a real error — execution simply stops early.
class _EvalExprStopped extends BytecodeRuntimeError {
  _EvalExprStopped() : super('evalExpr: stopped at backward jump');
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

  /// Per-frame register file — grows lazily as [Opcode.storeReg] fills slots.
  /// Registers are private to a frame; nested calls each get a fresh file.
  final List<dynamic> regs = [];

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

  /// Set by native calls that return a Future; the execute loop awaits this
  /// and pushes the resolved value onto the current frame's stack.
  Future<dynamic>? pendingFuture;
}

// ---------------------------------------------------------------------------
// Interpreter
// ---------------------------------------------------------------------------

class BytecodeInterpreter {
  final BytecodeProgram program;
  final Runtime runtime;
  final Map<int, dynamic Function(List<dynamic>)> _nativeFunctions = {};

  /// Threads spawned by [Opcode.call] on `THREAD(fn)`.
  /// Indexed by [Thread.id] so [JOIN] can locate them.
  final List<BytecodeThread> _spawnedThreads = [];

  /// When true, any backward jump throws [_EvalExprStopped] instead of
  /// looping.  Set exclusively by [evalExpr].
  bool _stopOnBackwardJump = false;

  BytecodeInterpreter(this.program, this.runtime) {
    _bridgeRuntime();
    _registerBytecodeNatives();
  }

  /// Override the runtime-bridged THREAD / JOIN with versions that know how
  /// to create and schedule [BytecodeThread]s.
  void _registerBytecodeNatives() {
    registerNative('THREAD', (args) {
      final callable = args[0];
      if (callable is! BytecodeCallable) {
        throw BytecodeRuntimeError('THREAD() requires a callable, got $callable');
      }
      final thread = BytecodeThread(
        initialFrame: _makeFrame(callable.chunk, [], callable.capturedScope),
      );
      final handle = Thread(id: _spawnedThreads.length);
      _spawnedThreads.add(thread);
      return handle;
    });

    registerNative('JOIN', (args) {
      final handle = args[0];
      if (handle is! Thread) {
        throw BytecodeRuntimeError('JOIN() requires a Thread, got $handle');
      }
      final idx = handle.id;
      if (idx < 0 || idx >= _spawnedThreads.length) return null;
      final target = _spawnedThreads[idx];
      // Cooperative round-robin: tick ALL spawned threads until target finishes.
      while (target.isRunning) {
        for (final t in _spawnedThreads) {
          if (t.isRunning) _tickOne(t);
        }
      }
      if (target.error != null) throw target.error!;
      return null; // SHQL JOIN does not surface the thread's return value
    });
  }

  /// Register a native Dart function callable from bytecode via [Opcode.call].
  /// [name] is case-insensitive (uppercased to match SHQL™ identifier semantics).
  void registerNative(String name, dynamic Function(List<dynamic> args) fn) {
    _nativeFunctions[runtime.identifiers.include(name.toUpperCase())] = fn;
  }

  /// Bridge all native functions registered in [runtime] into this
  /// interpreter's native function table.
  ///
  /// Called automatically by the constructor.  The [ExecutionContext] /
  /// [ExecutionNode] parameters expected by instance functions are satisfied
  /// with `null` — all current implementations ignore them for the operations
  /// that the bytecode VM exercises.
  void _bridgeRuntime() {
    // Nullary: String name → (ctx?, caller?) fn
    for (final e in runtime.nullaryFunctionEntries) {
      final id = runtime.identifiers.include(e.key);
      _nativeFunctions[id] = (_) => e.value(null, null);
    }

    // Static unary: String name → (caller?, p1) fn
    for (final e in Runtime.unaryFunctions.entries) {
      final id = runtime.identifiers.include(e.key);
      _nativeFunctions[id] = (args) => e.value(null, args[0]);
    }

    // Instance unary: int id → (ctx?, caller?, p1) fn
    for (final e in runtime.unaryFunctionRegistrations.entries) {
      _nativeFunctions[e.key] = (args) => e.value(null, null, args[0]);
    }

    // Static binary: String name → (p1, p2) fn
    for (final e in Runtime.binaryFunctions.entries) {
      final id = runtime.identifiers.include(e.key);
      _nativeFunctions[id] = (args) => e.value(args[0], args[1]);
    }

    // Instance binary: int id → (ctx, caller, p1, p2) fn
    // Special case: _EXTERN(name, args) dispatches to static maps — handle
    // without ExecutionContext so bytecode can call it with null context.
    final externId = runtime.identifiers.include('_EXTERN');
    _nativeFunctions[externId] = (args) {
      final name = args[0] as String;
      final fnArgs = args[1];
      final unary = Runtime.unaryFunctions[name];
      if (unary != null && fnArgs is List && fnArgs.length == 1) {
        return unary(null, fnArgs[0]);
      }
      final binary = Runtime.binaryFunctions[name];
      if (binary != null && fnArgs is List && fnArgs.length == 2) {
        return binary(fnArgs[0], fnArgs[1]);
      }
      final ternary = Runtime.ternaryFunctions[name];
      if (ternary != null && fnArgs is List && fnArgs.length == 3) {
        return ternary(fnArgs[0], fnArgs[1], fnArgs[2]);
      }
      return null;
    };
    for (final e in runtime.binaryFunctionRegistrations.entries) {
      if (e.key == externId) continue; // already registered above
      _nativeFunctions[e.key] = (args) => e.value(null, null, args[0], args[1]);
    }

    // Static ternary: String name → (p1, p2, p3) fn
    for (final e in Runtime.ternaryFunctions.entries) {
      final id = runtime.identifiers.include(e.key);
      _nativeFunctions[id] = (args) => e.value(args[0], args[1], args[2]);
    }

    // Instance ternary: int id → (ctx?, caller?, p1, p2, p3) fn
    for (final e in runtime.ternaryFunctionRegistrations.entries) {
      _nativeFunctions[e.key] = (args) => e.value(null, null, args[0], args[1], args[2]);
    }
  }

  /// Build the parent scope chain for the main frame.
  ///
  /// Chain (innermost first): boundValues scope → startingScope → globalScope.
  Scope _buildParentScope({
    Scope? startingScope,
    Map<String, dynamic>? boundValues,
  }) {
    Scope parent = startingScope ?? runtime.globalScope;
    if (boundValues != null && boundValues.isNotEmpty) {
      final bound = Scope(Object(), parent: parent);
      for (final entry in boundValues.entries) {
        bound.setVariable(
          runtime.identifiers.include(entry.key.toUpperCase()),
          entry.value,
        );
      }
      return bound;
    }
    return parent;
  }

  /// Create a new [BytecodeThread] ready to run [chunkName] with [args].
  ///
  /// [startingScope] is injected between [runtime.globalScope] and the frame
  /// scope — the same role it plays in [Engine.execute].
  /// [boundValues] are pushed on top of [startingScope] (or globalScope).
  BytecodeThread createThread(
    String chunkName,
    List<dynamic> args, {
    Scope? startingScope,
    Map<String, dynamic>? boundValues,
  }) {
    final parentScope = _buildParentScope(
      startingScope: startingScope,
      boundValues: boundValues,
    );
    return BytecodeThread(
      initialFrame: _makeFrame(program[chunkName], args, parentScope),
    );
  }

  /// Convenience: run [chunkName] to completion on a single thread.
  /// Backward-compatible with the old async API; pure computation never yields.
  Future<dynamic> execute([
    String chunkName = 'main',
    List<dynamic> args = const [],
  ]) async {
    final thread = createThread(chunkName, args);
    while (thread.isRunning) {
      _tickOne(thread);
      if (thread.pendingFuture != null) {
        final value = await thread.pendingFuture!;
        thread.pendingFuture = null;
        if (thread.isRunning) thread.currentFrame.stack.add(value);
      }
    }
    if (thread.error != null) throw thread.error!;
    return thread.result;
  }

  /// Like [execute] but with an optional injected [startingScope] and
  /// [boundValues] — mirrors [Engine.execute] with those parameters.
  ///
  /// Unlike [createThread], the top-level frame's scope IS [parentScope]
  /// directly (no child scope is created), so that top-level [Opcode.storeVar]
  /// stores into the persistent global/starting scope.  This enables
  /// multi-run patterns where stdlib is loaded in one call and src is
  /// executed in a subsequent call against the same runtime.
  Future<dynamic> executeScoped(
    String chunkName, {
    List<dynamic> args = const [],
    Scope? startingScope,
    Map<String, dynamic>? boundValues,
  }) async {
    final frameScope = _buildParentScope(
      startingScope: startingScope,
      boundValues: boundValues,
    );
    final chunk = program[chunkName];
    final thread = BytecodeThread(
      initialFrame: BytecodeFrame(chunk: chunk, pc: 0, stack: [], scope: frameScope),
    );
    while (thread.isRunning) {
      _tickOne(thread);
      if (thread.pendingFuture != null) {
        final value = await thread.pendingFuture!;
        thread.pendingFuture = null;
        if (thread.isRunning) thread.currentFrame.stack.add(value);
      }
    }
    if (thread.error != null) throw thread.error!;
    return thread.result;
  }

  /// Evaluate [expression] like [Engine.evalExpr]: compile and run the
  /// program, but stop (without error) the moment a backward jump is
  /// encountered.  Returns the top-of-stack value at that point, or `null`
  /// if execution stopped early.
  ///
  /// This is used by awesome_calculator to show live results for in-progress
  /// programs that may contain loops — the first partial result is returned
  /// rather than running forever.
  static Future<dynamic> evalExpr(
    String expression, {
    Runtime? runtime,
    ConstantsSet? constantsSet,
  }) async {
    constantsSet ??= Runtime.prepareConstantsSet();
    runtime ??= Runtime.prepareRuntime(constantsSet);
    final tree = Parser.parse(expression, constantsSet, sourceCode: expression);
    final program = BytecodeCompiler.compile(tree, constantsSet);
    final interp = BytecodeInterpreter(program, runtime);
    interp._stopOnBackwardJump = true;
    final thread = interp.createThread('main', const []);
    while (thread.isRunning) {
      interp._tickOne(thread);
      if (thread.pendingFuture != null) {
        final value = await thread.pendingFuture!;
        thread.pendingFuture = null;
        if (thread.isRunning) thread.currentFrame.stack.add(value);
      }
    }
    if (thread.error is _EvalExprStopped) return null;
    if (thread.error != null) throw thread.error!;
    return thread.result;
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
    } catch (e, st) {
      thread.error =
          e is BytecodeRuntimeError ? e : BytecodeRuntimeError('$e\n$st');
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

      case Opcode.dup:
        stack.add(stack.last);

      case Opcode.loadReg:
        final idx = instr.operand;
        stack.add(idx < frame.regs.length ? frame.regs[idx] : null);

      case Opcode.storeReg:
        final idx = instr.operand;
        while (frame.regs.length <= idx) frame.regs.add(null);
        frame.regs[idx] = stack.removeLast();

      // ---- Arithmetic ------------------------------------------------------

      case Opcode.add:
        final b = stack.removeLast(), a = stack.removeLast();
        if (a is List && b is List) {
          stack.add([...a, ...b]);
        } else {
          stack.add(a + b);
        }

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

      case Opcode.pow:
        final b = stack.removeLast(), a = stack.removeLast();
        stack.add(math.pow(a as num, b as num));

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
        if (_stopOnBackwardJump && instr.operand < frame.pc) {
          throw _EvalExprStopped();
        }
        frame.pc = instr.operand;

      case Opcode.jumpFalse:
        if (!_truthy(stack.removeLast())) {
          if (_stopOnBackwardJump && instr.operand < frame.pc) {
            throw _EvalExprStopped();
          }
          frame.pc = instr.operand;
        }

      case Opcode.jumpTrue:
        if (_truthy(stack.removeLast())) {
          if (_stopOnBackwardJump && instr.operand < frame.pc) {
            throw _EvalExprStopped();
          }
          frame.pc = instr.operand;
        }

      case Opcode.jumpNull:
        // Peek (do NOT pop) — leave value on stack for the non-null path.
        if (stack.last == null) {
          if (_stopOnBackwardJump && instr.operand < frame.pc) {
            throw _EvalExprStopped();
          }
          frame.pc = instr.operand;
        }

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
          final result = callable.fn(callArgs);
          if (result is Future) {
            thread.pendingFuture = result;
            return; // caller will await and push result
          }
          stack.add(result);
        } else if (callable is num && argCount == 1 && callArgs[0] is num) {
          // Implicit multiplication — the core SHQL calculator feature.
          // `42(2)` means `42 * 2`, matching CallExecutionNode's runtime fallback.
          stack.add(callable * (callArgs[0] as num));
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
          final value = _unwrap(obj.resolveIdentifier(id));
          if (value is BytecodeCallable) {
            // Re-bind method: insert the object's scope so the method body
            // can access sibling fields via normal variable lookup.
            final objectScope = Scope(
              obj,
              constants: value.capturedScope.constants,
              parent: value.capturedScope,
            );
            stack.add(BytecodeCallable(value.chunk, objectScope));
          } else {
            stack.add(value);
          }
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
        } else if (container is Map) {
          stack.add(container[idx]);
        } else if (container is String) {
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
        } else if (container is Map) {
          container[idx] = value;
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
        // THIS = self-reference, mirrors ObjectLiteralNode
        obj.setVariable(runtime.identifiers.include('THIS'), obj);
        stack.add(obj);

      // Like makeObject but uses the Object already backing the current scope
      // (created by the preceding pushScope).  Closures compiled between
      // pushScope and makeObjectHere therefore capture a Scope that wraps THIS
      // very Object, so all object members — including those defined later in
      // the literal — are visible inside every method at call time.
      case Opcode.makeObjectHere:
        final pairCount2 = instr.operand;
        final obj2 = frame.scope.members; // reuse pushScope's Object
        final pairs2 = List<dynamic>.filled(pairCount2 * 2, null);
        for (var i = pairCount2 * 2 - 1; i >= 0; i--) {
          pairs2[i] = stack.removeLast();
        }
        for (var i = 0; i < pairCount2; i++) {
          final key = pairs2[i * 2] as String;
          final id = runtime.identifiers.include(key.toUpperCase());
          obj2.setVariable(id, pairs2[i * 2 + 1]);
        }
        obj2.setVariable(runtime.identifiers.include('THIS'), obj2);
        stack.add(obj2);

      case Opcode.makeMap:
        final pairCount = instr.operand;
        final pairs = List<dynamic>.filled(pairCount * 2, null);
        for (var i = pairCount * 2 - 1; i >= 0; i--) {
          pairs[i] = stack.removeLast();
        }
        final map = <dynamic, dynamic>{};
        for (var i = 0; i < pairCount; i++) {
          map[pairs[i * 2]] = pairs[i * 2 + 1];
        }
        stack.add(map);

      case Opcode.opIn:
        final rhs = stack.removeLast();
        final lhs = stack.removeLast();
        if (lhs == null || rhs == null) {
          stack.add(null);
        } else if (rhs is List || rhs is Set) {
          stack.add((rhs as Iterable).contains(lhs));
        } else if (rhs is Iterable) {
          stack.add(rhs.any((e) => e == lhs));
        } else {
          final l = lhs is String ? lhs : lhs.toString();
          final r = rhs is String ? rhs : rhs.toString();
          stack.add(r.contains(l));
        }

      case Opcode.opMatch:
        final rhs = stack.removeLast();
        final lhs = stack.removeLast();
        if (lhs == null || rhs == null) {
          stack.add(null);
        } else {
          final regex = RegExp(rhs.toString(), caseSensitive: false);
          stack.add(regex.hasMatch(lhs.toString()));
        }

      case Opcode.opNotMatch:
        final rhs = stack.removeLast();
        final lhs = stack.removeLast();
        if (lhs == null || rhs == null) {
          stack.add(null);
        } else {
          final regex = RegExp(rhs.toString(), caseSensitive: false);
          stack.add(!regex.hasMatch(lhs.toString()));
        }
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
