import 'dart:io';

import 'package:shql/bytecode/bytecode_codec.dart';
import 'package:shql/bytecode/bytecode_compiler.dart';
import 'package:shql/bytecode/bytecode_interpreter.dart';
import 'package:shql/bytecode/bytecode_pipeline.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/parser/constants_set.dart';
import 'package:shql/parser/parser.dart';
import 'package:test/test.dart';

void main() {
  late ConstantsSet cs;
  late Runtime pipelineRt;
  late BytecodeInterpreter pipelineVm;
  late Runtime testRt;

  setUpAll(() async {
    // Set up pipeline runtime
    cs = Runtime.prepareConstantsSet();
    pipelineRt = Runtime.prepareRuntime(cs);

    final stdlibSrc = File('assets/stdlib.shql').readAsStringSync();
    final lexerSrc = File('assets/shql_lexer.shql').readAsStringSync();
    final parserSrc = File('assets/shql_parser.shql').readAsStringSync();
    final compilerSrc = File('assets/shql_compiler.shql').readAsStringSync();
    final codecSrc = File('assets/shql_codec.shql').readAsStringSync();

    for (final src in [stdlibSrc, lexerSrc, parserSrc, compilerSrc, codecSrc]) {
      final tree = Parser.parse(src, cs, sourceCode: src);
      final prog = BytecodeCompiler.compile(tree, cs);
      await BytecodeInterpreter(prog, pipelineRt).executeScoped('main');
    }

    // Set up the pipeline invocation VM
    const invocSrc = '''
      tokens := lexer.tokenize(src);
      tree := parser.parse(tokens);
      prog := compiler.compile(tree, consts);
      dec := codec.decode(prog);
      [prog, dec]
    ''';
    final invocTree = Parser.parse(invocSrc, cs, sourceCode: invocSrc);
    final invocProg = BytecodeCompiler.compile(invocTree, cs);
    pipelineVm = BytecodeInterpreter(invocProg, pipelineRt);
  });

  setUp(() async {
    // Fresh test runtime with stdlib loaded
    cs = Runtime.prepareConstantsSet();
    testRt = Runtime.prepareRuntime(cs);
    final stdlibSrc = File('assets/stdlib.shql').readAsStringSync();
    final tree = Parser.parse(stdlibSrc, cs, sourceCode: stdlibSrc);
    final prog = BytecodeCompiler.compile(tree, cs);
    await BytecodeInterpreter(prog, testRt).executeScoped('main');
  });

  Future<dynamic> compileWithShqlAndRun(String src) async {
    final consts = {
      for (final e in Runtime.allConstants.entries)
        if (e.value is! bool) e.key: e.value,
    };
    final output = await pipelineVm.executeScoped(
      'main',
      boundValues: {'src': src, 'consts': consts},
    ) as List;
    final program = shqlMapToProgram(output[0] as Map);
    return BytecodeInterpreter(program, testRt).executeScoped('main');
  }

  test('STRING(IF TRUE THEN INT(x) ELSE x) — SHQL™ compiler', () async {
    final result = await compileWithShqlAndRun('''
      x := 75.0;
      STRING(IF TRUE THEN INT(x) ELSE x)
    ''');
    expect(result, '75');
  });

  test('Exact calculator formatted_result pattern — SHQL™ compiler', () async {
    final result = await compileWithShqlAndRun('''
      result := 75.0;
      index := 5;
      formatted_result := string(
          if index >= 4 then
              int (result)
          else
              result
          );
      formatted_result
    ''');
    expect(result, '75');
  });

  test('Full calculator.shql — SHQL™ pipeline call(1) for STRING', () async {
    final src = File('../awesome_calculator/assets/shql/calculator.shql').readAsStringSync();
    final consts = {
      for (final e in Runtime.allConstants.entries)
        if (e.value is! bool) e.key: e.value,
    };
    final output = await pipelineVm.executeScoped(
      'main',
      boundValues: {'src': src, 'consts': consts},
    ) as List;
    final disasm = (output[1] as List).cast<String>();
    final fmtIdx = disasm.indexWhere(
        (l) => l.contains('store_var') && l.contains('FORMATTED_RESULT'));
    expect(disasm[fmtIdx - 1], contains('call(1)'),
        reason: 'STRING should be called with 1 argument');
  });

  test('SHQL™ pipeline with ARGS global does not corrupt parser', () async {
    // Regression test: when ARGS is set on globalScope (like shqlc does),
    // the parser's internal "args" variable used to overwrite the global ARGS
    // instead of creating a local, causing wrong call arg counts.
    final src = File('../awesome_calculator/assets/shql/calculator.shql').readAsStringSync();
    final consts = {
      for (final e in Runtime.allConstants.entries)
        if (e.value is! bool) e.key: e.value,
    };

    final shqlCs = Runtime.prepareConstantsSet();
    final shqlRt = Runtime.prepareRuntime(shqlCs);
    // Set ARGS on globalScope — this used to corrupt the SHQL™ parser
    shqlRt.globalScope.setVariable(
      shqlRt.identifiers.include('ARGS'),
      ['some_file.shql'],
    );
    for (final name in ['stdlib', 'shql_lexer', 'shql_parser', 'shql_compiler', 'shql_codec']) {
      final bytes = File('assets/compiled/$name.shqlbc').readAsBytesSync();
      final prog = BytecodeDecoder.decode(bytes);
      await BytecodeInterpreter(prog, shqlRt).executeScoped('main');
    }

    const invocSrc = '''
      tokens := lexer.tokenize(src);
      tree := parser.parse(tokens);
      prog := compiler.compile(tree, consts);
      dec := codec.decode(prog);
      [prog, dec]
    ''';
    final invocTree = Parser.parse(invocSrc, shqlCs, sourceCode: invocSrc);
    final invocProg = BytecodeCompiler.compile(invocTree, shqlCs);
    final vm = BytecodeInterpreter(invocProg, shqlRt);
    final output = await vm.executeScoped(
      'main',
      boundValues: {'src': src, 'consts': consts},
    ) as List;
    final disasm = (output[1] as List).cast<String>();
    final fmtIdx = disasm.indexWhere(
        (l) => l.contains('store_var') && l.contains('FORMATTED_RESULT'));
    expect(disasm[fmtIdx - 1], contains('call(1)'),
        reason: 'STRING should be call(1) even with ARGS in global scope');
  });

  test('Full calculator.shql — Dart vs SHQL™ pipeline output matches', () async {
    final src = File('../awesome_calculator/assets/shql/calculator.shql').readAsStringSync();
    final consts = {
      for (final e in Runtime.allConstants.entries)
        if (e.value is! bool) e.key: e.value,
    };

    // Dart-bootstrapped pipeline
    final dartOutput = await pipelineVm.executeScoped(
      'main',
      boundValues: {'src': src, 'consts': consts},
    ) as List;
    final dartDisasm = (dartOutput[1] as List).cast<String>();

    // SHQL™-compiled pipeline (from .shqlbc)
    final shqlCs = Runtime.prepareConstantsSet();
    final shqlRt = Runtime.prepareRuntime(shqlCs);
    for (final name in ['stdlib', 'shql_lexer', 'shql_parser', 'shql_compiler', 'shql_codec']) {
      final bytes = File('assets/compiled/$name.shqlbc').readAsBytesSync();
      final prog = BytecodeDecoder.decode(bytes);
      await BytecodeInterpreter(prog, shqlRt).executeScoped('main');
    }
    const invocSrc2 = '''
      tokens := lexer.tokenize(src);
      tree := parser.parse(tokens);
      prog := compiler.compile(tree, consts);
      dec := codec.decode(prog);
      [prog, dec]
    ''';
    final invocTree2 = Parser.parse(invocSrc2, shqlCs, sourceCode: invocSrc2);
    final invocProg2 = BytecodeCompiler.compile(invocTree2, shqlCs);
    final shqlPipelineVm = BytecodeInterpreter(invocProg2, shqlRt);
    final shqlOutput = await shqlPipelineVm.executeScoped(
      'main',
      boundValues: {'src': src, 'consts': consts},
    ) as List;
    final shqlDisasm = (shqlOutput[1] as List).cast<String>();

    expect(shqlDisasm, dartDisasm,
        reason: 'SHQL™-compiled pipeline must match Dart-compiled pipeline');
  });
}
