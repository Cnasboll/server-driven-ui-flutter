/// Console I/O and file system bindings for SHQL programs.
///
/// Registers native functions for file I/O, command-line arguments, and
/// environment variables into the static [Runtime] function maps so they
/// are accessible via `_EXTERN` wrappers in stdlib.shql.
import 'dart:io';
import 'dart:typed_data';

import 'package:shql/bytecode/bytecode_codec.dart';
import 'package:shql/bytecode/bytecode_pipeline.dart';
import 'package:shql/execution/runtime/runtime.dart';

/// Register all console/file-system native functions.
///
/// Functions are added to the static [Runtime.unaryFunctions] /
/// [Runtime.binaryFunctions] maps so they work via `_EXTERN` from SHQL.
/// Console I/O callbacks and ARGS are set on the [rt] instance.
///
/// Available after this call (via stdlib _EXTERN wrappers):
///   FILE_READ(path)           → String contents
///   FILE_WRITE(path, content) → null (writes text file)
///   FILE_READ_BYTES(path)     → List<int> bytes
///   FILE_WRITE_BYTES(path, bytes) → null (writes binary file)
///   FILE_EXISTS(path)         → bool
///   DIR_CREATE(path)          → null (creates directory recursively)
///   EXIT(code)                → never returns
///   ENV(name)                 → String? environment variable value
///   STDERR(value)             → null (writes to stderr)
///   _ENCODE_PROGRAM(progMap)  → List<int> binary bytecode
void registerConsoleBindings(Runtime rt, List<String> args) {
  // Console I/O callbacks
  rt.printFunction = (value) => stdout.writeln(value);
  rt.promptFunction = (prompt) async {
    stdout.write(prompt);
    return stdin.readLineSync() ?? '';
  };
  rt.readlineFunction = () async => stdin.readLineSync() ?? '';

  // Command-line arguments — accessible as ARGS variable
  rt.globalScope.setVariable(
    rt.identifiers.include('ARGS'),
    args,
  );

  // ---- Register in static maps for _EXTERN access ----

  // Unary
  Runtime.unaryFunctions['FILE_READ'] = (caller, path) {
    return File(path as String).readAsStringSync();
  };
  Runtime.unaryFunctions['FILE_READ_BYTES'] = (caller, path) {
    return File(path as String).readAsBytesSync().toList();
  };
  Runtime.unaryFunctions['FILE_EXISTS'] = (caller, path) {
    return File(path as String).existsSync();
  };
  Runtime.unaryFunctions['DIR_CREATE'] = (caller, path) {
    Directory(path as String).createSync(recursive: true);
    return null;
  };
  Runtime.unaryFunctions['EXIT'] = (caller, code) {
    exit(code is int ? code : 0);
  };
  Runtime.unaryFunctions['ENV'] = (caller, name) {
    return Platform.environment[name as String];
  };
  Runtime.unaryFunctions['STDERR'] = (caller, value) {
    stderr.writeln(value);
    return null;
  };
  Runtime.unaryFunctions['_ENCODE_PROGRAM'] = (caller, progMap) {
    final program = shqlMapToProgram(progMap as Map);
    return BytecodeEncoder.encode(program).toList();
  };

  // Binary
  Runtime.binaryFunctions['FILE_WRITE'] = (path, content) {
    File(path as String).writeAsStringSync(content as String);
    return null;
  };
  Runtime.binaryFunctions['FILE_WRITE_BYTES'] = (path, bytes) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList((bytes as List).cast<int>());
    File(path as String).writeAsBytesSync(data);
    return null;
  };
}
