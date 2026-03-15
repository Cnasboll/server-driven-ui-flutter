/// Utilities for working with the SHQL™ self-hosting compiler pipeline.
///
/// [shqlMapToProgram] converts the Map output of the SHQL™ compiler into a
/// typed [BytecodeProgram].  [canonicalCodec] produces the same human-readable
/// listing format as `shql_codec.shql`'s `codec.decode()`.
library;

import 'package:shql/bytecode/bytecode.dart';

/// Convert the Map produced by the SHQL™ self-hosting compiler to a typed
/// [BytecodeProgram] that [BytecodeInterpreter] can execute.
///
/// The SHQL™ compiler outputs `{ "chunks": { name: chunk, ... } }` where each
/// chunk has `name`, `params`, `constants`, and `code` (list of instruction
/// maps with `op` and optional `operand`).  ChunkRefs are stored as strings
/// of the form `'@chunkName'` (length > 1).
BytecodeProgram shqlMapToProgram(Map program) {
  final opcodeByMnemonic = {for (final op in Opcode.values) op.mnemonic: op};
  final chunksMap = program['chunks'] as Map;
  final chunks = <String, BytecodeChunk>{};
  for (final entry in chunksMap.entries) {
    final name = entry.key as String;
    final chunk = entry.value as Map;
    final constants = (chunk['constants'] as List).map<dynamic>((c) {
      if (c is String && c.length > 1 && c.startsWith('@')) {
        return ChunkRef(c.substring(1));
      }
      return c;
    }).toList();
    final code = (chunk['code'] as List).map((instr) {
      final m = instr as Map;
      final op = opcodeByMnemonic[m['op'] as String]!;
      final operand = m['operand'];
      return Instruction(op, operand != null ? (operand as num).toInt() : 0);
    }).toList();
    chunks[name] = BytecodeChunk(
      name: name,
      constants: constants,
      params: ((chunk['params'] as List?) ?? []).cast<String>(),
      code: code,
    );
  }
  return BytecodeProgram(chunks);
}

/// Produces the same human-readable listing format as `shql_codec.shql`'s
/// `codec.decode()`, so Dart and SHQL™ codec outputs can be compared directly.
///
/// Chunks are emitted in canonical order: `main` first, then all other chunks
/// sorted alphabetically by name — matching [BytecodeEncoder]'s canonical
/// ordering.
List<String> canonicalCodec(BytecodeProgram program) {
  String fmtConst(dynamic val) {
    if (val == null) return 'null';
    if (val == true) return 'true';
    if (val == false) return 'false';
    if (val is ChunkRef) return '.${val.name}';
    return val.toString();
  }

  String fmtInstr(Instruction instr, List<dynamic> constants) {
    final op = instr.op;
    if (!op.hasOperand) return op.mnemonic;
    final arg = instr.operand;
    var resolved = '';
    if (op == Opcode.pushConst || op == Opcode.makeClosure) {
      resolved = '  -- ${fmtConst(constants[arg])}';
    } else if (op == Opcode.loadVar || op == Opcode.storeVar ||
        op == Opcode.getMember || op == Opcode.setMember) {
      resolved = '  -- ${constants[arg]}';
    }
    return '${op.mnemonic}($arg)$resolved';
  }

  List<String> chunkLines(BytecodeChunk chunk) {
    final out = <String>[];
    out.add('CHUNK ${chunk.name} (${chunk.params.join(', ')})');
    for (var i = 0; i < chunk.constants.length; i++) {
      out.add('  CONST  $i: ${fmtConst(chunk.constants[i])}');
    }
    out.add('  CODE:');
    for (var i = 0; i < chunk.code.length; i++) {
      out.add('    $i: ${fmtInstr(chunk.code[i], chunk.constants)}');
    }
    return out;
  }

  final sorted = [...program.chunks.values]
    ..sort((a, b) => a.name == 'main'
        ? -1
        : b.name == 'main'
            ? 1
            : a.name.compareTo(b.name));
  final out = <String>[];
  for (final chunk in sorted) {
    out.addAll(chunkLines(chunk));
  }
  return out;
}
