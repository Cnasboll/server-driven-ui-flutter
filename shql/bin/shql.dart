/// SHQL™ Runner — executes compiled SHQL bytecode (.shqlbc) files.
///
/// Usage:  dart run shql:shql [options] <program.shqlbc>
///
/// Options:
///   --stdlib <file>   Path to compiled stdlib (default: assets/compiled/stdlib.shqlbc)
import 'dart:io';

import 'package:shql/bytecode/bytecode_codec.dart';
import 'package:shql/bytecode/bytecode_interpreter.dart';
import 'package:shql/execution/runtime/runtime.dart';

Future<void> main(List<String> args) async {
  // ---- Parse arguments ----
  String? stdlibPath;
  String? programPath;

  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--stdlib' && i + 1 < args.length) {
      stdlibPath = args[++i];
    } else if (args[i].startsWith('-')) {
      stderr.writeln('Unknown option: ${args[i]}');
      exit(1);
    } else if (programPath == null) {
      programPath = args[i];
    } else {
      stderr.writeln('Unexpected argument: ${args[i]}');
      exit(1);
    }
  }

  if (programPath == null) {
    stderr.writeln('Usage: shql [--stdlib <file>] <program.shqlbc>');
    exit(1);
  }

  // ---- Resolve stdlib path ----
  final assetsDir = Directory.current.path.endsWith('shql')
      ? '${Directory.current.path}/assets'
      : '${Directory.current.path}/shql/assets';
  stdlibPath ??= '$assetsDir/compiled/stdlib.shqlbc';

  // ---- Set up runtime ----
  final cs = Runtime.prepareConstantsSet();
  final rt = Runtime.prepareRuntime(cs);

  // ---- Load stdlib ----
  final stdlibFile = File(stdlibPath);
  if (stdlibFile.existsSync()) {
    final stdlib = BytecodeDecoder.decode(stdlibFile.readAsBytesSync());
    await BytecodeInterpreter(stdlib, rt).executeScoped('main');
  }

  // ---- Load and run the program ----
  final progFile = File(programPath);
  if (!progFile.existsSync()) {
    stderr.writeln('File not found: $programPath');
    exit(1);
  }

  final program = BytecodeDecoder.decode(progFile.readAsBytesSync());
  final result = await BytecodeInterpreter(program, rt).executeScoped('main');

  if (result != null) {
    stdout.writeln(result);
  }
}
