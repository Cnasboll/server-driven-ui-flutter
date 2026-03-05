/// Core data structures for the SHQL™ bytecode VM.
library;

// ---------------------------------------------------------------------------
// Opcodes
// ---------------------------------------------------------------------------

/// Every instruction the VM can execute.
enum Opcode {
  // --- Stack / variables ---

  /// Push `constants[operand]` onto the value stack.
  /// If the constant is a [ChunkRef] a [_Closure] capturing the current
  /// scope is pushed instead.
  pushConst,

  /// Load a variable by name. `constants[operand]` must be a [String].
  loadVar,

  /// Pop top and store to variable. `constants[operand]` is the name.
  storeVar,

  /// Discard the top of the value stack.
  pop,

  // --- Arithmetic ---
  add,
  sub,
  mul,
  div,
  mod,

  /// Unary negation.
  neg,

  // --- Comparison (push bool) ---
  cmpEq,
  cmpNeq,
  cmpLt,
  cmpLte,
  cmpGt,
  cmpGte,

  // --- Logic ---
  logAnd,
  logOr,
  logNot,

  // --- Control flow ---

  /// Unconditional jump. `operand` = target instruction index.
  jump,

  /// Pop top; jump if falsy. `operand` = target instruction index.
  jumpFalse,

  /// Pop top; jump if truthy. `operand` = target instruction index.
  jumpTrue,

  // --- Scope ---

  /// Push a new child scope (for BEGIN/END blocks).
  pushScope,

  /// Pop the current scope back to its parent.
  /// The required `pop_scope` instructions are emitted by the compiler
  /// before every [jump] / [jumpFalse] / [jumpTrue] that exits the block,
  /// so scope depth is always resolved at compile time.
  popScope,

  // --- Functions / closures ---

  /// Pop `operand` args (last-pushed = last arg), then pop callable;
  /// call it and push the result.
  call,

  /// Push a closure: chunk referenced by `constants[operand]` (a [ChunkRef])
  /// capturing the current scope.
  makeClosure,

  /// Return the top of the value stack to the caller.
  ret,

  // --- Object / list access ---

  /// Pop object; push `object.member` where the name = `constants[operand]`.
  getMember,

  /// Pop value then object; set `object.member = value`.
  setMember,

  /// Pop index then container; push `container[index]`.
  getIndex,

  /// Pop value, index, container; set `container[index] = value`.
  setIndex,

  /// Pop `operand` items (last-pushed = last element) and push a [List].
  makeList,

  /// Pop `operand * 2` items (key, value pairs) and push a [Map].
  makeObject,
}

// ---------------------------------------------------------------------------
// Instruction
// ---------------------------------------------------------------------------

/// A single bytecode instruction — an opcode plus an optional integer operand.
class Instruction {
  final Opcode op;
  final int operand;

  const Instruction(this.op, [this.operand = 0]);

  @override
  String toString() => operand != 0 ? '${op.name} $operand' : op.name;
}

// ---------------------------------------------------------------------------
// Constant pool value types
// ---------------------------------------------------------------------------

/// A reference to another [BytecodeChunk] stored in the constant pool.
/// Used by [Opcode.pushConst] and [Opcode.makeClosure] to look up a chunk
/// by name and wrap it in a closure at runtime.
class ChunkRef {
  final String name;

  const ChunkRef(this.name);

  @override
  String toString() => '.$name';

  @override
  bool operator ==(Object other) => other is ChunkRef && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

// ---------------------------------------------------------------------------
// BytecodeChunk
// ---------------------------------------------------------------------------

/// A compiled unit: one function body or the top-level program.
class BytecodeChunk {
  /// The chunk's name, unique within a [BytecodeProgram].
  final String name;

  /// Mixed constant pool — elements may be [int], [double], [String], or
  /// [ChunkRef].  [String] entries that are used as operands to [loadVar] /
  /// [storeVar] / [getMember] / [setMember] are treated as identifier names
  /// resolved against the runtime scope at execution time.
  final List<dynamic> constants;

  /// Parameter names in call order (index 0 = first argument).
  final List<String> params;

  /// The instruction stream.
  final List<Instruction> code;

  const BytecodeChunk({
    required this.name,
    required this.constants,
    required this.params,
    required this.code,
  });

  @override
  String toString() => 'BytecodeChunk($name, ${code.length} instructions)';
}

// ---------------------------------------------------------------------------
// BytecodeProgram
// ---------------------------------------------------------------------------

/// A complete compiled program: a map from chunk name → [BytecodeChunk].
/// The entry point is always the chunk named `"main"`.
class BytecodeProgram {
  final Map<String, BytecodeChunk> chunks;

  const BytecodeProgram(this.chunks);

  BytecodeChunk operator [](String name) {
    final chunk = chunks[name];
    if (chunk == null) throw StateError('No chunk named "$name"');
    return chunk;
  }

  bool hasChunk(String name) => chunks.containsKey(name);

  @override
  String toString() => 'BytecodeProgram(${chunks.keys.join(', ')})';
}
