import 'package:shql/bytecode/bytecode_codec.dart';
import 'package:shql/bytecode/bytecode_compiler.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/parser/parser.dart';

void main() {
  for (final src in ['10+2', '1+2', '42', 'x:=5; x']) {
    try {
      final cs = Runtime.prepareConstantsSet();
      final tree = Parser.parse(src, cs, sourceCode: src);
      final program = BytecodeCompiler.compile(tree, cs);
      final decoded = BytecodeDecoder.decode(BytecodeEncoder.encode(program));
      final chunk = decoded['main'];
      print('=== $src ===');
      print('  constants: ${chunk.constants}');
      for (final instr in chunk.code) {
        final op = (instr.op as dynamic);
        final m = op.mnemonic as String;
        if (op.hasOperand as bool) {
          print('  $m(${instr.operand})');
        } else {
          print('  $m');
        }
      }
    } catch (e, st) {
      print('ERROR for $src: $e\n$st');
    }
  }
}
