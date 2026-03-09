/// SHQLC — the SHQL™ compiler.
///
/// Identical to `shql` except the program is the hardcoded compiler
/// (shqlc.shqlbc) and the pipeline bytecodes are pre-loaded.
///
/// Usage:  dart run shql:shqlc [options] <source.shql> [source2.shql ...]
///
/// Options:
///   --toolchain <dir>   Directory with compiled pipeline files
///                        (default: assets/compiled/)
///   -o, --output <dir>  Output directory (default: same as source file)
import 'dart:io';

import 'package:shql/bytecode/bytecode_codec.dart';
import 'package:shql/bytecode/bytecode_console.dart';
import 'package:shql/bytecode/bytecode_interpreter.dart';
import 'package:shql/execution/runtime/runtime.dart';

const _pipelineFiles = [
  'stdlib',
  'shql_lexer',
  'shql_parser',
  'shql_compiler',
  'shql_codec',
];

Future<void> main(List<String> args) async {
  // ---- Resolve toolchain directory ----
  final assetsDir = Directory.current.path.endsWith('shql')
      ? '${Directory.current.path}/assets'
      : '${Directory.current.path}/shql/assets';
  final toolchainDir = '$assetsDir/compiled';

  // ---- Set up runtime ----
  final cs = Runtime.prepareConstantsSet();
  final rt = Runtime.prepareRuntime(cs);
  registerConsoleBindings(rt, args);

  // ---- Load pipeline ----
  for (final name in _pipelineFiles) {
    final file = File('$toolchainDir/$name.shqlbc');
    if (!file.existsSync()) {
      stderr.writeln('Missing toolchain file: ${file.path}');
      stderr.writeln('Run shql_bootstrap first to compile the pipeline.');
      exit(1);
    }
    final prog = BytecodeDecoder.decode(file.readAsBytesSync());
    await BytecodeInterpreter(prog, rt).executeScoped('main');
  }

  // ---- Set runtime constants for the SHQL compiler ----
  rt.globalScope.setVariable(
    rt.identifiers.include('__CONSTS'),
    {
      for (final e in Runtime.allConstants.entries)
        if (e.value is! bool) e.key: e.value,
    },
  );

  // ---- Load and run the compiler program ----
  final progFile = File('$toolchainDir/shqlc.shqlbc');
  if (!progFile.existsSync()) {
    stderr.writeln('Missing compiler program: ${progFile.path}');
    stderr.writeln('Run shql_bootstrap first.');
    exit(1);
  }

  final program = BytecodeDecoder.decode(progFile.readAsBytesSync());
  final result = await BytecodeInterpreter(program, rt).executeScoped('main');

  if (result != null) {
    stdout.writeln(result);
  }
}
