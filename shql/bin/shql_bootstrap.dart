/// SHQL™ Bootstrap — compiles the self-hosting pipeline using the SHQL
/// compiler itself: the Dart compiler bootstraps the pipeline into the
/// bytecode VM, then the SHQL compiler compiles itself (and shqlc.shql)
/// to produce the final binary bytecode (.shqlbc) and canonical
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

/// Pipeline files that must be loaded into the VM before compilation.
const _pipelineFiles = [
  'stdlib',
  'shql_lexer',
  'shql_parser',
  'shql_compiler',
  'shql_codec',
];

/// All files to compile (pipeline + the compiler driver program).
const _allFiles = [
  ..._pipelineFiles,
  'shqlc',
];

/// The SHQL script that drives the pipeline: tokenize → parse → compile →
/// decode, returning [compiledProgram, disassemblyLines].
const _invocationSrc = '''
tokens  := lexer.tokenize(src);
tree    := parser.parse(tokens);
prog    := compiler.compile_with_consts(tree, consts);
dec     := codec.decode(prog);
[prog, dec]
''';

Future<void> main(List<String> args) async {
  final assetsDir = Directory.current.path.endsWith('shql')
      ? '${Directory.current.path}/assets'
      : '${Directory.current.path}/shql/assets';
  final outputDir = args.isNotEmpty ? args[0] : '$assetsDir/compiled';

  await Directory(outputDir).create(recursive: true);

  final cs = Runtime.prepareConstantsSet();
  final rt = Runtime.prepareRuntime(cs);

  // ---- Bootstrap: Dart-compile the pipeline into the bytecode VM ----
  for (final name in _pipelineFiles) {
    final src = File('$assetsDir/$name.shql').readAsStringSync();
    final prog = BytecodeCompiler.compile(
      Parser.parse(src, cs, sourceCode: src),
      cs,
    );
    await BytecodeInterpreter(prog, rt).executeScoped('main');
  }

  // ---- Runtime constants for the SHQL compiler to inline ----
  final consts = {
    for (final e in Runtime.allConstants.entries)
      if (e.value is! bool) e.key: e.value,
  };

  // ---- Compile invocation script (tiny wrapper) ----
  final invocTree = Parser.parse(_invocationSrc, cs, sourceCode: _invocationSrc);
  final invocProg = BytecodeCompiler.compile(invocTree, cs);
  final pipelineVm = BytecodeInterpreter(invocProg, rt);

  // ---- Use the SHQL compiler to compile all files ----
  for (final name in _allFiles) {
    final src = File('$assetsDir/$name.shql').readAsStringSync();

    final result = await pipelineVm.executeScoped(
      'main',
      boundValues: {'src': src, 'consts': consts},
    ) as List;

    final progMap = result[0] as Map;
    final disasmLines = (result[1] as List).cast<String>();

    // Convert SHQL compiler output to typed program, then encode
    final program = shqlMapToProgram(progMap);
    final encoded = BytecodeEncoder.encode(program);

    // Write binary bytecode
    File('$outputDir/$name.shqlbc').writeAsBytesSync(encoded);

    // Write canonical disassembly
    File('$outputDir/$name.shqla').writeAsStringSync('${disasmLines.join('\n')}\n');

    stdout.writeln('  $name.shql -> $name.shqlbc (${encoded.length} bytes) + $name.shqla');
  }

  stdout.writeln('Bootstrap complete: $outputDir');
}
