/// Binary codec and text disassembler for the SHQL™ bytecode VM.
///
/// ## Binary format
///
/// ```
/// Header:   magic(4) 'SHQL' | version(1) 0x01 | chunk_count(2) u16-LE
/// Chunk:    name(1+N) u8-len + UTF-8
///           param_count(1) u8
///           params(…)      u8-len + UTF-8  ×param_count
///           const_count(2) u16-LE
///           constants(…)   tag(1) + payload  ×const_count
///           instr_count(2) u16-LE
///           instructions(…) opcode(1) [+ operand(4) i32-LE]  ×instr_count
/// Constant tags:
///   0x00 null   (no payload)
///   0x01 int    8 bytes i64-LE
///   0x02 double 8 bytes f64-LE
///   0x03 String u16-LE length + UTF-8 bytes
///   0x04 ChunkRef u8 length + UTF-8 name
/// ```
///
/// The opcode byte is `Opcode.index`; operands are present iff
/// `Opcode.hasOperand` is true.  The text disassembler in [BytecodeDisassembler]
/// is the inverse of [BytecodeParser], enabling full round-trips:
///
///   text ──parse──▶ program ──encode──▶ bytes
///                      │                  │
///               disassemble            decode
///                      │                  │
///                    text              program
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:shql/bytecode/bytecode.dart';

// ---------------------------------------------------------------------------
// Encoder
// ---------------------------------------------------------------------------

class BytecodeEncoder {
  static const _magic = [0x53, 0x48, 0x51, 0x4C]; // 'SHQL'
  static const _version = 0x01;

  static Uint8List encode(BytecodeProgram program) {
    final buf = <int>[];
    buf.addAll(_magic);
    buf.add(_version);
    _u16(buf, program.chunks.length);
    // Canonical order: 'main' first, remaining chunks sorted alphabetically.
    // This makes the binary output deterministic regardless of insertion order,
    // so Dart-compiled and SHQL-compiled programs produce identical bytes.
    final sorted = [...program.chunks.values]
      ..sort((a, b) => a.name == 'main'
          ? -1
          : b.name == 'main'
              ? 1
              : a.name.compareTo(b.name));
    for (final chunk in sorted) {
      _encodeChunk(buf, chunk);
    }
    return Uint8List.fromList(buf);
  }

  static void _encodeChunk(List<int> buf, BytecodeChunk chunk) {
    _str8(buf, chunk.name);
    buf.add(chunk.params.length);
    for (final p in chunk.params) {
      _str8(buf, p);
    }
    _u16(buf, chunk.constants.length);
    for (final c in chunk.constants) {
      _encodeConstant(buf, c);
    }
    _u16(buf, chunk.code.length);
    for (final instr in chunk.code) {
      buf.add(instr.op.index);
      if (instr.op.hasOperand) _i32(buf, instr.operand);
    }
  }

  static void _encodeConstant(List<int> buf, dynamic value) {
    if (value == null) {
      buf.add(0x00);
    } else if (value is int) {
      buf.add(0x01);
      _i64(buf, value);
    } else if (value is double) {
      buf.add(0x02);
      _f64(buf, value);
    } else if (value is String) {
      buf.add(0x03);
      _str16(buf, value);
    } else if (value is ChunkRef) {
      buf.add(0x04);
      _str8(buf, value.name);
    } else if (value is bool) {
      buf.add(value ? 0x05 : 0x06);
    } else {
      throw StateError('Unsupported constant type: ${value.runtimeType}');
    }
  }

  // Primitives
  static void _u16(List<int> buf, int v) {
    final bd = ByteData(2)..setUint16(0, v, Endian.little);
    buf.addAll(bd.buffer.asUint8List());
  }

  static void _i32(List<int> buf, int v) {
    final bd = ByteData(4)..setInt32(0, v, Endian.little);
    buf.addAll(bd.buffer.asUint8List());
  }

  static void _i64(List<int> buf, int v) {
    final bd = ByteData(8)..setInt64(0, v, Endian.little);
    buf.addAll(bd.buffer.asUint8List());
  }

  static void _f64(List<int> buf, double v) {
    final bd = ByteData(8)..setFloat64(0, v, Endian.little);
    buf.addAll(bd.buffer.asUint8List());
  }

  static void _str8(List<int> buf, String s) {
    final bytes = utf8.encode(s);
    buf.add(bytes.length);
    buf.addAll(bytes);
  }

  static void _str16(List<int> buf, String s) {
    final bytes = utf8.encode(s);
    _u16(buf, bytes.length);
    buf.addAll(bytes);
  }
}

// ---------------------------------------------------------------------------
// Decoder
// ---------------------------------------------------------------------------

class BytecodeDecoder {
  final Uint8List _bytes;
  int _pos = 0;

  BytecodeDecoder._(this._bytes);

  static BytecodeProgram decode(Uint8List bytes) =>
      BytecodeDecoder._(bytes)._decode();

  BytecodeProgram _decode() {
    _expectMagic();
    final version = _byte();
    if (version != 0x01) {
      throw FormatException('Unsupported bytecode version: $version');
    }
    final chunkCount = _u16();
    final chunks = <String, BytecodeChunk>{};
    for (var i = 0; i < chunkCount; i++) {
      final chunk = _decodeChunk();
      chunks[chunk.name] = chunk;
    }
    return BytecodeProgram(chunks);
  }

  BytecodeChunk _decodeChunk() {
    final name = _str8();
    final paramCount = _byte();
    final params = [for (var i = 0; i < paramCount; i++) _str8()];
    final constCount = _u16();
    final constants = [for (var i = 0; i < constCount; i++) _decodeConstant()];
    final instrCount = _u16();
    final code = [for (var i = 0; i < instrCount; i++) _decodeInstruction()];
    return BytecodeChunk(
      name: name,
      constants: constants,
      params: params,
      code: code,
    );
  }

  dynamic _decodeConstant() {
    final tag = _byte();
    return switch (tag) {
      0x00 => null,
      0x01 => _i64(),
      0x02 => _f64(),
      0x03 => _str16(),
      0x04 => ChunkRef(_str8()),
      0x05 => true,
      0x06 => false,
      _ => throw FormatException('Unknown constant tag: 0x${tag.toRadixString(16)}'),
    };
  }

  Instruction _decodeInstruction() {
    final opByte = _byte();
    if (opByte >= Opcode.values.length) {
      throw FormatException('Unknown opcode byte: $opByte');
    }
    final op = Opcode.values[opByte];
    return op.hasOperand ? Instruction(op, _i32()) : Instruction(op);
  }

  void _expectMagic() {
    final magic = [_byte(), _byte(), _byte(), _byte()];
    if (magic[0] != 0x53 || magic[1] != 0x48 ||
        magic[2] != 0x51 || magic[3] != 0x4C) {
      throw FormatException('Invalid SHQL bytecode magic bytes');
    }
  }

  int _byte() => _bytes[_pos++];

  int _u16() {
    final bd = ByteData.sublistView(_bytes, _pos, _pos + 2);
    _pos += 2;
    return bd.getUint16(0, Endian.little);
  }

  int _i32() {
    final bd = ByteData.sublistView(_bytes, _pos, _pos + 4);
    _pos += 4;
    return bd.getInt32(0, Endian.little);
  }

  int _i64() {
    final bd = ByteData.sublistView(_bytes, _pos, _pos + 8);
    _pos += 8;
    return bd.getInt64(0, Endian.little);
  }

  double _f64() {
    final bd = ByteData.sublistView(_bytes, _pos, _pos + 8);
    _pos += 8;
    return bd.getFloat64(0, Endian.little);
  }

  String _str8() {
    final len = _byte();
    final s = utf8.decode(_bytes.sublist(_pos, _pos + len));
    _pos += len;
    return s;
  }

  String _str16() {
    final len = _u16();
    final s = utf8.decode(_bytes.sublist(_pos, _pos + len));
    _pos += len;
    return s;
  }
}

// ---------------------------------------------------------------------------
// Disassembler  (BytecodeProgram → canonical text)
// ---------------------------------------------------------------------------

/// Produces canonical bytecode text from a [BytecodeProgram].
///
/// The output is accepted by [BytecodeParser] without modification, enabling
/// the round-trip: `text → parse → encode → decode → disassemble → text`.
/// Comments are not preserved (they carry no semantic content).
class BytecodeDisassembler {
  static String disassemble(BytecodeProgram program) {
    final buf = StringBuffer();
    for (final chunk in program.chunks.values) {
      _disassembleChunk(buf, chunk);
    }
    return buf.toString();
  }

  static void _disassembleChunk(StringBuffer buf, BytecodeChunk chunk) {
    buf.writeln('.chunk ${chunk.name}:');

    if (chunk.params.isNotEmpty) {
      buf.writeln('  .params:');
      for (final p in chunk.params) {
        buf.writeln('    $p');
      }
    }

    if (chunk.constants.isNotEmpty) {
      buf.writeln('  .constants:');
      for (var i = 0; i < chunk.constants.length; i++) {
        buf.writeln('    $i: ${_formatConstant(chunk.constants[i])}');
      }
    }

    buf.writeln('  .code:');
    for (final instr in chunk.code) {
      if (instr.op.hasOperand) {
        buf.writeln('    ${instr.op.mnemonic} ${instr.operand}');
      } else {
        buf.writeln('    ${instr.op.mnemonic}');
      }
    }
  }

  static String _formatConstant(dynamic value) {
    if (value == null) return 'null';
    if (value is int) return '$value';
    if (value is double) return '$value';
    if (value is String) return '"$value"';
    if (value is ChunkRef) return '.${value.name}';
    throw StateError('Unsupported constant type: ${value.runtimeType}');
  }
}
