/// Stack-based interpreter for the SHQL™ bytecode VM.
///
/// Variables are stored in the same [Scope] / [Object] chain used by the
/// existing execution-node runtime, and identifier names are interned via
/// [Runtime.identifiers] so that bytecode and traditional SHQL™ programs
/// share the same identifier space.  This is the foundation that will allow
/// the bytecode compiler to replace [ExecutionNode]s while keeping the
/// [Runtime] and [Scope] infrastructure intact.
library;

import 'package:shql/bytecode/bytecode.dart';
import 'package:shql/execution/runtime/runtime.dart';

// ---------------------------------------------------------------------------
// Public errors
// ---------------------------------------------------------------------------

class BytecodeRuntimeError implements Exception {
  final String message;

  BytecodeRuntimeError(this.message);

  @override
  String toString() => 'BytecodeRuntimeError: $message';
}

// ---------------------------------------------------------------------------
// Callable wrapper for bytecode closures
// ---------------------------------------------------------------------------

/// A compiled function that can be pushed onto the value stack and invoked
/// via [Opcode.call].  Holds the chunk to execute and the [Scope] captured
/// at the point of [Opcode.makeClosure] / [Opcode.pushConst] for a [ChunkRef].
class BytecodeCallable {
  final BytecodeChunk chunk;
  final Scope capturedScope;

  BytecodeCallable(this.chunk, this.capturedScope);

  @override
  String toString() => 'BytecodeCallable(${chunk.name})';
}

// ---------------------------------------------------------------------------
// Interpreter
// ---------------------------------------------------------------------------

class BytecodeInterpreter {
  final BytecodeProgram program;
  final Runtime runtime;

  BytecodeInterpreter(this.program, this.runtime);

  /// Execute the named chunk (default: `"main"`) with optional positional [args].
  /// Execution begins in a child scope of [Runtime.globalScope].
  Future<dynamic> execute([
    String chunkName = 'main',
    List<dynamic> args = const [],
  ]) {
    return _run(program[chunkName], args, runtime.globalScope);
  }

  Future<dynamic> _run(
    BytecodeChunk chunk,
    List<dynamic> args,
    Scope parentScope,
  ) async {
    final stack = <dynamic>[];

    // Each call frame gets its own scope child, just as ExecutionNodes do.
    var scope = Scope(Object(), parent: parentScope);

    // Bind named parameters into the new scope.
    for (var i = 0; i < chunk.params.length && i < args.length; i++) {
      final id = runtime.identifiers.include(chunk.params[i].toUpperCase());
      scope.setVariable(id, args[i]);
    }

    int pc = 0;
    while (pc < chunk.code.length) {
      final instr = chunk.code[pc++];

      switch (instr.op) {
        // ---- Stack / variables -------------------------------------------

        case Opcode.pushConst:
          final c = chunk.constants[instr.operand];
          // ChunkRef constants auto-close over the current scope.
          stack.add(c is ChunkRef ? BytecodeCallable(program[c.name], scope) : c);

        case Opcode.loadVar:
          final id = _id(chunk, instr.operand);
          final (raw, _, _) = scope.resolveIdentifier(id);
          stack.add(_unwrap(raw));

        case Opcode.storeVar:
          final id = _id(chunk, instr.operand);
          scope.setVariable(id, stack.removeLast());

        case Opcode.pop:
          stack.removeLast();

        // ---- Arithmetic -------------------------------------------------

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

        // ---- Comparison -------------------------------------------------

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

        // ---- Logic ------------------------------------------------------

        case Opcode.logAnd:
          final b = stack.removeLast(), a = stack.removeLast();
          stack.add(_truthy(a) && _truthy(b));

        case Opcode.logOr:
          final b = stack.removeLast(), a = stack.removeLast();
          stack.add(_truthy(a) || _truthy(b));

        case Opcode.logNot:
          stack.add(!_truthy(stack.removeLast()));

        // ---- Control flow -----------------------------------------------

        case Opcode.jump:
          pc = instr.operand;

        case Opcode.jumpFalse:
          if (!_truthy(stack.removeLast())) pc = instr.operand;

        case Opcode.jumpTrue:
          if (_truthy(stack.removeLast())) pc = instr.operand;

        // ---- Scope ------------------------------------------------------

        /// A BEGIN/END block simply pushes a new child scope.  break/continue
        /// emit the required pop_scope instructions before their jump so scope
        /// depth is always resolved at compile time — no runtime scope counting
        /// is needed.
        case Opcode.pushScope:
          scope = Scope(Object(), parent: scope);

        case Opcode.popScope:
          scope = scope.parent ?? scope;

        // ---- Functions / closures ---------------------------------------

        case Opcode.call:
          final argCount = instr.operand;
          final callArgs = List<dynamic>.filled(argCount, null);
          for (var i = argCount - 1; i >= 0; i--) {
            callArgs[i] = stack.removeLast();
          }
          final callable = stack.removeLast();
          stack.add(await _call(callable, callArgs));

        case Opcode.makeClosure:
          final ref = chunk.constants[instr.operand];
          final name = ref is ChunkRef ? ref.name : ref as String;
          stack.add(BytecodeCallable(program[name], scope));

        case Opcode.ret:
          return stack.isEmpty ? null : stack.removeLast();

        // ---- Object / list access ---------------------------------------

        case Opcode.getMember:
          final id = _id(chunk, instr.operand);
          final obj = stack.removeLast();
          if (obj is Object) {
            stack.add(_unwrap(obj.resolveIdentifier(id)));
          } else {
            throw BytecodeRuntimeError(
              'get_member: expected SHQL Object, got $obj',
            );
          }

        case Opcode.setMember:
          final id = _id(chunk, instr.operand);
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

    // Implicit return: top of stack, or null if empty.
    return stack.isEmpty ? null : stack.last;
  }

  Future<dynamic> _call(dynamic callable, List<dynamic> args) async {
    if (callable is BytecodeCallable) {
      return _run(callable.chunk, args, callable.capturedScope);
    }
    throw BytecodeRuntimeError('Cannot call $callable');
  }

  /// Resolve the constant at [index] as an identifier integer ID.
  /// The constant must be a [String] (the identifier name).
  int _id(BytecodeChunk chunk, int index) {
    final name = chunk.constants[index] as String;
    return runtime.identifiers.include(name.toUpperCase());
  }

  /// Unwrap a [Variable] wrapper, pass everything else through unchanged.
  static dynamic _unwrap(dynamic raw) =>
      raw is Variable ? raw.value : raw;

  static bool _truthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.isNotEmpty;
    if (value is List) return value.isNotEmpty;
    return true;
  }
}
