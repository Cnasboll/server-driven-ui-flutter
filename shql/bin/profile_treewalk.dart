/// Profile the tree-walker bootstrap to find bottlenecks.
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
  final assetsDir = '${Directory.current.path}/assets';

  final cs = Runtime.prepareConstantsSet();
  final rt = Runtime.prepareRuntime(cs);
  registerConsoleBindings(rt, args);

  final consts = {
    for (final e in Runtime.allConstants.entries)
      if (e.value is! bool) e.key: e.value,
  };

  for (final name in _pipelineFiles) {
    final src = File('$assetsDir/$name.shql').readAsStringSync();
    stderr.writeln('Loading $name.shql (${src.length} chars)...');
    final sw = Stopwatch()..start();
    await Engine.execute(src, runtime: rt, constantsSet: cs);
    sw.stop();
    stderr.writeln('  $name.shql loaded in ${sw.elapsedMilliseconds}ms');
  }

  stderr.writeln('\nCompiling "1+2" through the SHQL™ pipeline...');
  final sw2 = Stopwatch()..start();
  await Engine.execute('''
    tokens := lexer.tokenize(src);
    tree := parser.parse(tokens);
    prog := compiler.compile(tree, consts);
    codec.decode(prog)
  ''', runtime: rt, constantsSet: cs, boundValues: {'src': '1+2', 'consts': consts});
  sw2.stop();
  stderr.writeln('  Compiled "1+2" in ${sw2.elapsedMilliseconds}ms');

  final stdlibSrc = File('$assetsDir/stdlib.shql').readAsStringSync();
  stderr.writeln('\n--- Profiling stdlib.shql (${stdlibSrc.length} chars) step by step ---');

  stderr.writeln('  Tokenizing...');
  final swTok = Stopwatch()..start();
  final tokens = await Engine.execute(
    'lexer.tokenize(src)',
    runtime: rt, constantsSet: cs, boundValues: {'src': stdlibSrc},
  );
  swTok.stop();
  final tokenCount = (tokens as List?)?.length ?? -1;
  stderr.writeln('  Tokenize: ${swTok.elapsedMilliseconds}ms ($tokenCount tokens)');

  stderr.writeln('  Parsing...');
  final swParse = Stopwatch()..start();
  final tree = await Engine.execute(
    'parser.parse(toks)',
    runtime: rt, constantsSet: cs, boundValues: {'toks': tokens},
  );
  swParse.stop();
  stderr.writeln('  Parse: ${swParse.elapsedMilliseconds}ms');

  stderr.writeln('  Compiling...');
  final swComp = Stopwatch()..start();
  final prog = await Engine.execute(
    'compiler.compile(tr, consts)',
    runtime: rt, constantsSet: cs, boundValues: {'tr': tree, 'consts': consts},
  );
  swComp.stop();
  stderr.writeln('  Compile: ${swComp.elapsedMilliseconds}ms');

  stderr.writeln('  Decoding...');
  final swDec = Stopwatch()..start();
  await Engine.execute(
    'codec.decode(pg)',
    runtime: rt, constantsSet: cs, boundValues: {'pg': prog},
  );
  swDec.stop();
  stderr.writeln('  Decode: ${swDec.elapsedMilliseconds}ms');

  stderr.writeln('\n  Total: ${swTok.elapsedMilliseconds + swParse.elapsedMilliseconds + swComp.elapsedMilliseconds + swDec.elapsedMilliseconds}ms');

  stderr.writeln('\n--- Full bootstrap simulation ---');
  final allFiles = ['stdlib', 'console_io', 'shql_lexer', 'shql_parser', 'shql_compiler', 'shql_codec', 'shqlc', 'shql_bootstrap'];
  final swTotal = Stopwatch()..start();
  for (final name in allFiles) {
    final path = '$assetsDir/$name.shql';
    if (!File(path).existsSync()) {
      stderr.writeln('  SKIP $name.shql (not found)');
      continue;
    }
    final fileSrc = File(path).readAsStringSync();
    final swFile = Stopwatch()..start();
    try {
      await Engine.execute('''
        _tokens := lexer.tokenize(_src);
        _tree := parser.parse(_tokens);
        _prog := compiler.compile(_tree, _consts);
        codec.decode(_prog)
      ''', runtime: rt, constantsSet: cs, boundValues: {'_src': fileSrc, '_consts': consts});
      swFile.stop();
      stderr.writeln('  $name.shql: ${swFile.elapsedMilliseconds}ms (${fileSrc.length} chars)');
    } catch (e) {
      swFile.stop();
      stderr.writeln('  $name.shql: FAILED after ${swFile.elapsedMilliseconds}ms - $e');
    }
  }
  swTotal.stop();
  stderr.writeln('  Bootstrap total: ${swTotal.elapsedMilliseconds}ms');
}
