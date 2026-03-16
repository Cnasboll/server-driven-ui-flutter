/// SHQL™ Bootstrap — recompiles all pipeline files from source using the SHQL™
/// compiler itself, then compiles shql.dart and shqlc.dart to native binaries.
///
/// Usage:  dart run shql:shql_bootstrap [output_dir]
import 'dart:io';

import 'package:shql/bytecode/bytecode_console.dart';
import 'package:shql/engine/engine.dart';
import 'package:shql/execution/runtime/runtime.dart';

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

  final cs = Runtime.prepareConstantsSet();
  final rt = Runtime.prepareRuntime(cs);
  registerConsoleBindings(rt, args);

  stderr.writeln('Loading SHQL™ pipeline...');
  final swLoad = Stopwatch()..start();
  for (final name in _pipelineFiles) {
    final file = File('$assetsDir/$name.shql');
    if (!file.existsSync()) {
      stderr.writeln('Missing: ${file.path}');
      exit(1);
    }
    await Engine.execute(file.readAsStringSync(), runtime: rt, constantsSet: cs);
  }
  swLoad.stop();
  stderr.writeln('Pipeline loaded in ${swLoad.elapsedMilliseconds}ms\n');

  final bootstrapFile = File('$assetsDir/shql_bootstrap.shql');
  if (!bootstrapFile.existsSync()) {
    stderr.writeln('Missing: ${bootstrapFile.path}');
    exit(1);
  }
  stderr.writeln('Running bootstrap...');
  final swBoot = Stopwatch()..start();
  await Engine.execute(
    bootstrapFile.readAsStringSync(),
    runtime: rt,
    constantsSet: cs,
    boundValues: {
      '__CONSTS': {
        for (final e in Runtime.allConstants.entries)
          if (e.value is! bool) e.key: e.value,
      },
      '__ASSETS_DIR': assetsDir,
      '__OUTPUT_DIR': outputDir,
    },
  );
  swBoot.stop();
  stderr.writeln('\nBootstrap completed in ${swBoot.elapsedMilliseconds}ms');

  final binDir = assetsDir.replaceFirst(RegExp(r'/assets$'), '/bin');
  for (final name in ['shql', 'shqlc']) {
    stderr.writeln('Compiling $name.dart to native binary...');
    final result = await Process.run(
      'dart', ['compile', 'exe', '$binDir/$name.dart'],
    );
    if (result.stdout.toString().isNotEmpty) stdout.write(result.stdout);
    if (result.stderr.toString().isNotEmpty) stderr.write(result.stderr);
  }
}
