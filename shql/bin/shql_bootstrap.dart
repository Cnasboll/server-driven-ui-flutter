/// SHQL™ Bootstrap — compiles the self-hosting pipeline using the Dart
/// compiler and saves each file as binary bytecode (.shqlbc) and canonical
/// disassembly (.shqla).
///
/// Usage:  dart run shql:shql_bootstrap [output_dir]
///
/// Default output directory: assets/compiled/
import 'dart:io';

import 'package:shql/bytecode/bytecode_codec.dart';
import 'package:shql/bytecode/bytecode_compiler.dart';
import 'package:shql/bytecode/bytecode_interpreter.dart';
import 'package:shql/bytecode/bytecode_pipeline.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/parser/parser.dart';

const _pipelineFiles = [
  'stdlib',
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

  await Directory(outputDir).create(recursive: true);

  final cs = Runtime.prepareConstantsSet();
  final rt = Runtime.prepareRuntime(cs);

  for (final name in _pipelineFiles) {
    final src = File('$assetsDir/$name.shql').readAsStringSync();
    final prog = BytecodeCompiler.compile(
      Parser.parse(src, cs, sourceCode: src),
      cs,
    );
    final encoded = BytecodeEncoder.encode(prog);
    final decoded = BytecodeDecoder.decode(encoded);

    // Write binary bytecode
    File('$outputDir/$name.shqlbc').writeAsBytesSync(encoded);

    // Write canonical disassembly
    final lines = canonicalCodec(decoded);
    File('$outputDir/$name.shqla').writeAsStringSync('${lines.join('\n')}\n');

    // Execute into runtime so later pipeline files can reference earlier ones
    await BytecodeInterpreter(prog, rt).executeScoped('main');

    stdout.writeln('  $name.shql -> $name.shqlbc (${encoded.length} bytes) + $name.shqla');
  }

  stdout.writeln('Bootstrap complete: $outputDir');
}
