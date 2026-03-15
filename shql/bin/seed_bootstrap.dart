/// One-time seed: produces initial .shqlbc files using the Dart compiler.
/// After seeding, use shql_bootstrap which is pure SHQL™.
import 'dart:io';
import 'package:shql/bytecode/bytecode_codec.dart';
import 'package:shql/bytecode/bytecode_compiler.dart';
import 'package:shql/bytecode/bytecode_pipeline.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/parser/parser.dart';

void main() async {
  final assetsDir = '${Directory.current.path}/assets';
  final outputDir = '$assetsDir/compiled';
  await Directory(outputDir).create(recursive: true);
  final cs = Runtime.prepareConstantsSet();
  final files = ['stdlib', 'console_io', 'shql_lexer', 'shql_parser',
                 'shql_compiler', 'shql_codec', 'shqlc', 'shql_bootstrap'];
  for (final name in files) {
    final src = File('$assetsDir/$name.shql').readAsStringSync();
    final prog = BytecodeCompiler.compile(Parser.parse(src, cs, sourceCode: src), cs);
    final encoded = BytecodeEncoder.encode(prog);
    File('$outputDir/$name.shqlbc').writeAsBytesSync(encoded);
    final disasm = canonicalCodec(BytecodeDecoder.decode(encoded));
    File('$outputDir/$name.shqla').writeAsStringSync('${disasm.join('\n')}\n');
    stdout.writeln('  $name.shql -> $name.shqlbc (${encoded.length} bytes)');
  }
  stdout.writeln('Seed complete');
}
