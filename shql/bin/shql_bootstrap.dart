/// SHQL™ Bootstrap — loads the pre-compiled pipeline and bootstrap program
/// via the bytecode VM, then runs the SHQL bootstrap which recompiles
/// everything from source.
///
/// No Dart compiler (BytecodeCompiler) is used. Everything runs as compiled
/// SHQL bytecode.
///
/// Usage:  dart run shql:shql_bootstrap [output_dir]
///
/// Default output directory: assets/compiled/
import 'dart:io';

import 'package:shql/bytecode/bytecode_codec.dart';
import 'package:shql/bytecode/bytecode_console.dart';
import 'package:shql/bytecode/bytecode_interpreter.dart';
import 'package:shql/execution/runtime/runtime.dart';

/// Files loaded from compiled bytecode before running the bootstrap program.
const _pipelineFiles = [
  'stdlib',
  'console_io',
  'shql_lexer',
  'shql_parser',
  'shql_compiler',
  'shql_codec',
];

Future<void> main(List<String> args) async {
  final assetsDir = Directory.current.path.endsWith('shql')
      ? '${Directory.current.path}/assets'
      : '${Directory.current.path}/shql/assets';
  final outputDir = args.isNotEmpty ? args[0] : '$assetsDir/compiled';
  final toolchainDir = '$assetsDir/compiled';

  final cs = Runtime.prepareConstantsSet();
  final rt = Runtime.prepareRuntime(cs);
  registerConsoleBindings(rt, args);

  // ---- Load pipeline from pre-compiled bytecode ----
  for (final name in _pipelineFiles) {
    final file = File('$toolchainDir/$name.shqlbc');
    if (!file.existsSync()) {
      stderr.writeln('Missing: ${file.path}');
      stderr.writeln('Run the seed bootstrap first.');
      exit(1);
    }
    final prog = BytecodeDecoder.decode(file.readAsBytesSync());
    await BytecodeInterpreter(prog, rt).executeScoped('main');
  }

  // ---- Set variables for the bootstrap program ----
  rt.globalScope.setVariable(
    rt.identifiers.include('__CONSTS'),
    {
      for (final e in Runtime.allConstants.entries)
        if (e.value is! bool) e.key: e.value,
    },
  );
  rt.globalScope.setVariable(
    rt.identifiers.include('__ASSETS_DIR'),
    assetsDir,
  );
  rt.globalScope.setVariable(
    rt.identifiers.include('__OUTPUT_DIR'),
    outputDir,
  );

  // ---- Load and run the compiled bootstrap program ----
  final bootstrapFile = File('$toolchainDir/shql_bootstrap.shqlbc');
  if (!bootstrapFile.existsSync()) {
    stderr.writeln('Missing: ${bootstrapFile.path}');
    stderr.writeln('Run the seed bootstrap first.');
    exit(1);
  }
  final bootstrapProg = BytecodeDecoder.decode(bootstrapFile.readAsBytesSync());
  await BytecodeInterpreter(bootstrapProg, rt).executeScoped('main');
}
