/// Console I/O and file system bindings for the bytecode VM.
///
/// Registers native functions for file I/O, command-line arguments, and
/// environment variables so SHQL programs can drive the toolchain.
import 'dart:io';
import 'dart:typed_data';

import 'package:shql/bytecode/bytecode_codec.dart';
import 'package:shql/bytecode/bytecode_pipeline.dart';
import 'package:shql/execution/runtime/runtime.dart';

/// Register all console/file-system native functions on [rt].
///
/// After this call, SHQL programs can use (via stdlib _EXTERN wrappers):
///   FILE_READ(path)           → String contents
///   FILE_WRITE(path, content) → null (writes text file)
///   FILE_READ_BYTES(path)     → List<int> bytes
///   FILE_WRITE_BYTES(path, bytes) → null (writes binary file)
///   FILE_EXISTS(path)         → bool
///   DIR_CREATE(path)          → null (creates directory recursively)
///   EXIT(code)                → never returns
///   ENV(name)                 → String? environment variable value
void registerConsoleBindings(Runtime rt, List<String> args) {
  // Console I/O
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

  // File I/O — unary
  rt.setUnaryFunction('FILE_READ', (ctx, caller, path) {
    return File(path as String).readAsStringSync();
  });
  rt.setUnaryFunction('FILE_READ_BYTES', (ctx, caller, path) {
    return File(path as String).readAsBytesSync().toList();
  });
  rt.setUnaryFunction('FILE_EXISTS', (ctx, caller, path) {
    return File(path as String).existsSync();
  });
  rt.setUnaryFunction('DIR_CREATE', (ctx, caller, path) {
    Directory(path as String).createSync(recursive: true);
    return null;
  });
  rt.setUnaryFunction('EXIT', (ctx, caller, code) {
    exit(code is int ? code : 0);
  });
  rt.setUnaryFunction('ENV', (ctx, caller, name) {
    return Platform.environment[name as String];
  });

  // File I/O — binary
  rt.setBinaryFunction('FILE_WRITE', (ctx, caller, path, content) {
    File(path as String).writeAsStringSync(content as String);
    return null;
  });
  rt.setBinaryFunction('FILE_WRITE_BYTES', (ctx, caller, path, bytes) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList((bytes as List).cast<int>());
    File(path as String).writeAsBytesSync(data);
    return null;
  });

  // stderr
  rt.setUnaryFunction('STDERR', (ctx, caller, value) {
    stderr.writeln(value);
    return null;
  });

  // Bytecode encoding: SHQL compiler Map → binary bytes
  rt.setUnaryFunction('_ENCODE_PROGRAM', (ctx, caller, progMap) {
    final program = shqlMapToProgram(progMap as Map);
    return BytecodeEncoder.encode(program).toList();
  });
}
