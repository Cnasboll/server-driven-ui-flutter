/// SHQLC — the SHQL™ compiler.
///
/// Loads the pre-compiled self-hosting pipeline (from shql_bootstrap) and
/// compiles SHQL source files to binary bytecode (.shqlbc) and canonical
/// disassembly (.shqla).
///
/// Usage:  dart run shql:shqlc [options] <source.shql> [source2.shql ...]
///
/// Options:
///   --toolchain <dir>   Directory with compiled pipeline files
///                        (default: assets/compiled/)
///   -o, --output <dir>  Output directory (default: same as source file)
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
  // ---- Parse arguments ----
  String? toolchainDir;
  String? outputDir;
  final sourceFiles = <String>[];

  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--toolchain' && i + 1 < args.length) {
      toolchainDir = args[++i];
    } else if ((args[i] == '-o' || args[i] == '--output') && i + 1 < args.length) {
      outputDir = args[++i];
    } else if (args[i].startsWith('-')) {
      stderr.writeln('Unknown option: ${args[i]}');
      exit(1);
    } else {
      sourceFiles.add(args[i]);
    }
  }

  if (sourceFiles.isEmpty) {
    stderr.writeln('Usage: shqlc [--toolchain <dir>] [-o <dir>] <source.shql> ...');
    exit(1);
  }

  // ---- Resolve toolchain directory ----
  final assetsDir = Directory.current.path.endsWith('shql')
      ? '${Directory.current.path}/assets'
      : '${Directory.current.path}/shql/assets';
  toolchainDir ??= '$assetsDir/compiled';

  // ---- Load pipeline ----
  final cs = Runtime.prepareConstantsSet();
  final rt = Runtime.prepareRuntime(cs);

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

  // ---- Compile the invocation script (tiny Dart-compiled wrapper) ----
  final invocTree = Parser.parse(_invocationSrc, cs, sourceCode: _invocationSrc);
  final invocProg = BytecodeCompiler.compile(invocTree, cs);
  final pipelineVm = BytecodeInterpreter(invocProg, rt);

  // ---- Runtime constants for the SHQL compiler to inline ----
  final consts = {
    for (final e in Runtime.allConstants.entries)
      if (e.value is! bool) e.key: e.value,
  };

  // ---- Compile each source file ----
  for (final srcPath in sourceFiles) {
    final srcFile = File(srcPath);
    if (!srcFile.existsSync()) {
      stderr.writeln('File not found: $srcPath');
      exit(1);
    }
    final src = srcFile.readAsStringSync();
    final baseName = _baseName(srcPath);
    final outDir = outputDir ?? srcFile.parent.path;

    final result = await pipelineVm.executeScoped(
      'main',
      boundValues: {'src': src, 'consts': consts},
    ) as List;

    final progMap = result[0] as Map;
    final disasmLines = (result[1] as List).cast<String>();

    // Convert SHQL compiler output to typed program, then encode
    final program = shqlMapToProgram(progMap);
    final encoded = BytecodeEncoder.encode(program);

    // Write binary
    final bcPath = '$outDir/$baseName.shqlbc';
    File(bcPath).writeAsBytesSync(encoded);

    // Write canonical disassembly
    final asmPath = '$outDir/$baseName.shqla';
    File(asmPath).writeAsStringSync('${disasmLines.join('\n')}\n');

    stdout.writeln('  $srcPath -> $baseName.shqlbc (${encoded.length} bytes) + $baseName.shqla');
  }
}

String _baseName(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}
