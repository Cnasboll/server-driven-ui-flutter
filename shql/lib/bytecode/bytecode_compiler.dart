/// SHQL™ → bytecode compiler.
///
/// [BytecodeCompiler.compile] takes a [ParseTree] produced by [Parser.parse]
/// and the matching [ConstantsSet] (which holds the literal constants and
/// identifier names referenced by [ParseTree.qualifier]) and returns a
/// [BytecodeProgram] ready to be executed by [BytecodeInterpreter].
///
/// The design mirrors [Engine.createExecutionNode]: a flat switch on
/// [ParseTree.symbol] dispatches to private helpers that emit instructions
/// into a [ChunkBuilder].  [ParseTree] itself stays a pure data class with
/// no bytecode dependency.
///
/// ## External functions vs opcodes
///
/// Only primitive VM operations become opcodes (add, sub, cmp*, jump, …).
/// Language operators that delegate to external libraries — such as `^`
/// (exponentiation → `math.pow`) — are compiled as **native function calls**,
/// registered on the interpreter via [BytecodeInterpreter.registerNative].
/// This keeps the VM spec minimal and every future port (C++, JS, …) just
/// registers its own platform `pow` rather than hard-coding it as a dispatch
/// case.
library;

import 'package:shql/bytecode/bytecode.dart';
import 'package:shql/parser/constants_set.dart';
import 'package:shql/parser/parse_tree.dart';
import 'package:shql/tokenizer/token.dart';

// ---------------------------------------------------------------------------
// Error
// ---------------------------------------------------------------------------

class BytecodeCompileError implements Exception {
  final String message;

  BytecodeCompileError(this.message);

  @override
  String toString() => 'BytecodeCompileError: $message';
}

// ---------------------------------------------------------------------------
// ChunkBuilder — mutable builder for one BytecodeChunk
// ---------------------------------------------------------------------------

class ChunkBuilder {
  final String name;
  final List<String> params;
  final List<dynamic> _constants = [];
  final Map<dynamic, int> _constantIdx = {};
  final List<Instruction> _code = [];

  ChunkBuilder(this.name, [this.params = const []]);

  /// Add [value] to the constant pool (deduped). Returns the pool index.
  int addConst(dynamic value) => _constantIdx.putIfAbsent(value, () {
    _constants.add(value);
    return _constants.length - 1;
  });

  /// Add an identifier name to the pool (operand for loadVar / storeVar /
  /// getMember / setMember).  Identifier strings are uppercased by the
  /// interpreter's `_id()` at runtime, so case is normalised there.
  int addName(String name) => addConst(name);

  void emit(Opcode op) => _code.add(Instruction(op));
  void emit1(Opcode op, int operand) => _code.add(Instruction(op, operand));

  /// Emit a jump with a placeholder operand; returns the instruction index
  /// so the caller can [patchJump] once the target address is known.
  int emitJump(Opcode op) {
    emit1(op, -1);
    return _code.length - 1;
  }

  /// Patch jump at [idx] to target the current (next-to-emit) address.
  void patchJump(int idx) =>
      _code[idx] = Instruction(_code[idx].op, _code.length);

  /// Patch instruction at [idx] to the given absolute [target].
  void patchAt(int idx, int target) =>
      _code[idx] = Instruction(_code[idx].op, target);

  int get currentAddr => _code.length;

  // ---- Register allocation -------------------------------------------------

  int _nextReg = 0;

  /// Allocate the next available register index for this chunk.
  /// Registers are per-frame so each new chunk starts fresh at 0.
  int allocReg() => _nextReg++;

  BytecodeChunk build() => BytecodeChunk(
    name: name,
    constants: List.unmodifiable(_constants),
    params: List.unmodifiable(params),
    code: List.unmodifiable(_code),
  );
}

// ---------------------------------------------------------------------------
// BytecodeCompiler
// ---------------------------------------------------------------------------

/// Loop context for break / continue patching.
typedef _LoopCtx = ({
  List<int> breaks,    // indices of emitted break-jump placeholders
  List<int> continues, // indices of emitted continue-jump placeholders (FOR)
  int continueAddr,    // known target for WHILE/REPEAT (-1 = FOR: patch later)
});

class BytecodeCompiler {
  final ConstantsSet _cs;
  final Map<String, BytecodeChunk> _chunks = {};
  int _counter = 0;
  final List<_LoopCtx> _loopStack = [];

  BytecodeCompiler._(this._cs);

  // ---- Public entry point --------------------------------------------------

  static BytecodeProgram compile(ParseTree tree, ConstantsSet cs) {
    final c = BytecodeCompiler._(cs);
    final main = ChunkBuilder('main');
    c._compile(tree, main);
    main.emit(Opcode.ret); // implicit return of last expression
    c._chunks['main'] = main.build();
    return BytecodeProgram(Map.unmodifiable(c._chunks));
  }

  // ---- Helpers -------------------------------------------------------------

  String _freshName(String hint) => '__${hint}_${_counter++}';

  void _registerChunk(ChunkBuilder b) => _chunks[b.name] = b.build();

  // ---- Main dispatch (mirrors Engine.createExecutionNode) ------------------

  void _compile(ParseTree node, ChunkBuilder b) {
    switch (node.symbol) {
      // ---- Literals --------------------------------------------------------

      case Symbols.integerLiteral ||
          Symbols.floatLiteral ||
          Symbols.stringLiteral:
        b.emit1(
          Opcode.pushConst,
          b.addConst(_cs.getConstantByIndex(node.qualifier!)),
        );

      case Symbols.nullLiteral:
        b.emit1(Opcode.pushConst, b.addConst(null));

      // ---- Identifier (variable / function reference) ----------------------

      case Symbols.identifier:
        final id = node.qualifier!;
        final (constValue, constIndex) = _cs.getConstantByIdentifier(id);
        if (constIndex != null) {
          // Registered constant (TRUE, FALSE, PI, ANSWER, E, …) — inline value.
          b.emit1(Opcode.pushConst, b.addConst(constValue));
        } else {
          final name = _cs.identifiers.getByIndex(id)!;
          b.emit1(Opcode.loadVar, b.addName(name));
        }

      // ---- Binary arithmetic (null-aware: mirrors NullAwareBinaryNode) ------

      case Symbols.add:
        _nullAwareBinary(node, b, Opcode.add);
      case Symbols.sub:
        _nullAwareBinary(node, b, Opcode.sub);
      case Symbols.mul:
        _nullAwareBinary(node, b, Opcode.mul);
      case Symbols.div:
        _nullAwareBinary(node, b, Opcode.div);
      case Symbols.mod:
        _nullAwareBinary(node, b, Opcode.mod);

      // ^ → null-aware pow opcode (mirrors ExponentiationExecutionNode which
      // extends NullAwareBinaryNode).
      case Symbols.pow:
        _nullAwareBinary(node, b, Opcode.pow);

      // ---- Comparison ------------------------------------------------------

      // eq / neq: EqualityExecutionNode / NotEqualityExecutionNode extend
      // BinaryOperatorExecutionNode (NOT NullAwareBinaryNode) — no null check.
      case Symbols.eq:
        _binary(node, b, Opcode.cmpEq);
      case Symbols.neq:
        _binary(node, b, Opcode.cmpNeq);

      // lt / lte / gt / gte: null-aware (extend NullAwareBinaryNode).
      case Symbols.lt:
        _nullAwareBinary(node, b, Opcode.cmpLt);
      case Symbols.ltEq:
        _nullAwareBinary(node, b, Opcode.cmpLte);
      case Symbols.gt:
        _nullAwareBinary(node, b, Opcode.cmpGt);
      case Symbols.gtEq:
        _nullAwareBinary(node, b, Opcode.cmpGte);

      // ---- Logic (BooleanExecutionNode — NOT null-aware) -------------------

      case Symbols.and:
        _binary(node, b, Opcode.logAnd);
      case Symbols.or:
        _binary(node, b, Opcode.logOr);
      case Symbols.xor:
        // XOR with null-as-falsy: toBool(lhs) != toBool(rhs).
        // logAnd(x, true) acts as toBool(x) via _truthy() — null → false.
        _compile(node.children[0], b);
        b.emit1(Opcode.pushConst, b.addConst(true));
        b.emit(Opcode.logAnd);
        _compile(node.children[1], b);
        b.emit1(Opcode.pushConst, b.addConst(true));
        b.emit(Opcode.logAnd);
        b.emit(Opcode.cmpNeq);

      // ---- Pattern / membership (null-aware) --------------------------------

      case Symbols.inOp:
        _nullAwareBinary(node, b, Opcode.opIn);
      case Symbols.match:
        _nullAwareBinary(node, b, Opcode.opMatch);
      case Symbols.notMatch:
        _nullAwareBinary(node, b, Opcode.opNotMatch);

      // not / unaryMinus: null-aware (extend NullAwareUnaryNode).
      case Symbols.not:
        _nullAwareUnary(node, b, Opcode.logNot);

      case Symbols.unaryMinus:
        _nullAwareUnary(node, b, Opcode.neg);

      case Symbols.unaryPlus:
        _compile(node.children[0], b); // identity — no null-aware needed

      // ---- Statement sequences ---------------------------------------------

      case Symbols.program:
        _compileSequence(node.children, b);

      case Symbols.compoundStatement:
        b.emit(Opcode.pushScope);
        _compileSequence(node.children, b);
        b.emit(Opcode.popScope);

      // ---- Assignment ------------------------------------------------------

      case Symbols.assignment:
        _compileAssignment(node, b);

      // ---- Control flow ----------------------------------------------------

      case Symbols.ifStatement:
        _compileIf(node, b);
      case Symbols.whileLoop:
        _compileWhile(node, b);
      case Symbols.forLoop:
        _compileFor(node, b);
      case Symbols.repeatUntilLoop:
        _compileRepeatUntil(node, b);
      case Symbols.returnStatement:
        _compileReturn(node, b);
      case Symbols.breakStatement:
        _compileBreak(b);
      case Symbols.continueStatement:
        _compileContinue(b);

      // ---- Functions / closures --------------------------------------------

      case Symbols.call:
        _compileCall(node, b);
      case Symbols.lambdaExpression:
        _compileLambda(node, b);

      // ---- Collections -----------------------------------------------------

      case Symbols.list:
        _compileList(node, b);
      case Symbols.tuple:
        // Standalone tuple expression → same as list literal (produces a List).
        _compileList(node, b);
      case Symbols.map:
        _compileMap(node, b);
      case Symbols.objectLiteral:
        _compileObject(node, b);

      // ---- Member / index access -------------------------------------------

      case Symbols.memberAccess:
        _compileMemberAccess(node, b);

      // ---- Unhandled -------------------------------------------------------

      default:
        throw BytecodeCompileError(
          'Cannot compile symbol: ${node.symbol} '
          '(tokens: ${node.tokens.map((t) => t.lexeme).join(' ')})',
        );
    }
  }

  // ---- Binary helpers (plain and null-aware) --------------------------------

  void _binary(ParseTree node, ChunkBuilder b, Opcode op) {
    _compile(node.children[0], b);
    _compile(node.children[1], b);
    b.emit(op);
  }

  /// Emit a null check on the top-of-stack value using [dup].
  /// After this call the stack still has [val] on top.
  /// Returns the index of the [jumpTrue] placeholder that must be patched
  /// to the "result is null" path by the caller.
  int _emitNullCheck(ChunkBuilder b) {
    b.emit(Opcode.dup);                          // [val, val]
    b.emit1(Opcode.pushConst, b.addConst(null)); // [val, val, null]
    b.emit(Opcode.cmpEq);                        // [val, (val==null)]
    return b.emitJump(Opcode.jumpTrue);          // pops bool; [val] if not null
  }

  /// Emit null-aware binary op — mirrors [NullAwareBinaryNode]:
  /// if lhs or rhs is null the result is null, otherwise [op] is applied.
  void _nullAwareBinary(ParseTree node, ChunkBuilder b, Opcode op) {
    _compile(node.children[0], b);               // [lhs]
    final lhsNull = _emitNullCheck(b);           // [lhs]; jump→.null if null
    _compile(node.children[1], b);               // [lhs, rhs]
    final rhsNull = _emitNullCheck(b);           // [lhs, rhs]; jump→.null if null
    b.emit(op);                                  // [result]
    final done = b.emitJump(Opcode.jump);
    b.patchJump(rhsNull);  // .rhsNull: [lhs, rhs(null)]
    b.emit(Opcode.pop);    // [lhs]
    b.patchJump(lhsNull);  // .lhsNull: [lhs(null)] OR [lhs] from rhsNull path
    b.emit(Opcode.pop);    // []
    b.emit1(Opcode.pushConst, b.addConst(null));
    b.patchJump(done);
  }

  /// Emit null-aware unary op — mirrors [NullAwareUnaryNode]:
  /// if operand is null the result is null, otherwise [op] is applied.
  void _nullAwareUnary(ParseTree node, ChunkBuilder b, Opcode op) {
    _compile(node.children[0], b);               // [val]
    final isNull = _emitNullCheck(b);            // [val]; jump→.end if null
    b.emit(op);                                  // [result]
    b.patchJump(isNull);                         // .end: stack has [null] or [result]
  }

  // ---- Sequences -----------------------------------------------------------

  /// Compile [stmts] in order; emit [pop] after every statement except the
  /// last so only the final result remains on the stack.
  void _compileSequence(List<ParseTree> stmts, ChunkBuilder b) {
    if (stmts.isEmpty) {
      b.emit1(Opcode.pushConst, b.addConst(null));
      return;
    }
    for (var i = 0; i < stmts.length; i++) {
      _compile(stmts[i], b);
      if (i < stmts.length - 1) b.emit(Opcode.pop);
    }
  }

  // ---- Assignment ----------------------------------------------------------

  void _compileAssignment(ParseTree node, ChunkBuilder b) {
    final lhs = node.children[0];
    final rhs = node.children[1];

    if (lhs.symbol == Symbols.call) {
      // x[i] := v  is parsed as call(x, list([i])) := v → setIndex
      if (lhs.children.length > 1 &&
          lhs.children[1].symbol == Symbols.list) {
        _compile(lhs.children[0], b);             // container
        _compile(lhs.children[1].children[0], b); // index
        _compile(rhs, b);                         // value
        b.emit(Opcode.setIndex);
        return;
      }
      _compileFunctionDef(lhs, rhs, b);
      return;
    }
    if (lhs.symbol == Symbols.memberAccess) {
      _compileMemberAssign(lhs, rhs, b);
      return;
    }
    if (lhs.symbol == Symbols.identifier) {
      _compile(rhs, b);
      final name = _cs.identifiers.getByIndex(lhs.qualifier!)!;
      b.emit1(Opcode.storeVar, b.addName(name));
      // Assignment is an expression: leave the stored value on the stack.
      b.emit1(Opcode.loadVar, b.addName(name));
      return;
    }
    throw BytecodeCompileError(
      'Cannot compile assignment LHS: ${lhs.symbol}',
    );
  }

  void _compileFunctionDef(
    ParseTree callNode,
    ParseTree body,
    ChunkBuilder b,
  ) {
    final callable = callNode.children[0];
    if (callable.symbol != Symbols.identifier) {
      throw BytecodeCompileError(
        'Function definition LHS must be an identifier, got ${callable.symbol}',
      );
    }
    final funcName = _cs.identifiers.getByIndex(callable.qualifier!)!;
    final chunkName = _freshName(funcName);

    final params = <String>[];
    if (callNode.children.length > 1) {
      _collectParams(callNode.children[1], params);
    }

    final fn = ChunkBuilder(chunkName, params);
    _compile(body, fn);
    fn.emit(Opcode.ret);
    _registerChunk(fn);

    b.emit1(Opcode.makeClosure, b.addConst(ChunkRef(chunkName)));
    b.emit1(Opcode.storeVar, b.addName(funcName));
    b.emit1(Opcode.loadVar, b.addName(funcName));
  }

  void _collectParams(ParseTree node, List<String> out) {
    if (node.symbol == Symbols.tuple) {
      for (final child in node.children) {
        _collectParams(child, out);
      }
    } else if (node.symbol == Symbols.identifier) {
      out.add(_cs.identifiers.getByIndex(node.qualifier!)!);
    } else {
      throw BytecodeCompileError(
        'Unexpected node in parameter list: ${node.symbol}',
      );
    }
  }

  void _compileMemberAssign(ParseTree memberNode, ParseTree rhs, ChunkBuilder b) {
    _compile(memberNode.children[0], b); // push object
    _compile(rhs, b);                    // push new value
    final member = memberNode.children[1];
    if (member.symbol != Symbols.identifier) {
      throw BytecodeCompileError(
        'Member assign: expected identifier, got ${member.symbol}',
      );
    }
    final name = _cs.identifiers.getByIndex(member.qualifier!)!;
    b.emit1(Opcode.setMember, b.addName(name));
  }

  // ---- IF ------------------------------------------------------------------

  void _compileIf(ParseTree node, ChunkBuilder b) {
    // children: [condition, thenBranch, ?elseBranch]
    _compile(node.children[0], b);
    final jumpToElse = b.emitJump(Opcode.jumpFalse);

    _compile(node.children[1], b); // then

    if (node.children.length > 2) {
      final jumpToEnd = b.emitJump(Opcode.jump);
      b.patchJump(jumpToElse);
      _compile(node.children[2], b); // else
      b.patchJump(jumpToEnd);
    } else {
      // No ELSE: false path evaluates to null.
      final jumpToEnd = b.emitJump(Opcode.jump);
      b.patchJump(jumpToElse);
      b.emit1(Opcode.pushConst, b.addConst(null));
      b.patchJump(jumpToEnd);
    }
  }

  // ---- WHILE ---------------------------------------------------------------

  void _compileWhile(ParseTree node, ChunkBuilder b) {
    // children: [condition, body]
    //
    // Stack discipline: one "last result" slot is always maintained on the stack.
    //   push null            ← initial last-result (handles never-executed case)
    //   .loopTop:
    //     condition          ← [last-result, condition]
    //     jumpFalse .exit    ← condition consumed; [last-result] stays
    //     pop                ← discard last-result; stack empty
    //     <body>             ← body result pushed; [body-result]
    //     jump .loopTop
    //   .exit:               ← [last-result] on stack (null or last body value)
    //
    // BREAK/CONTINUE: fire at statement boundaries where the stack is empty
    // (last-result was already popped). Push null first to restore balance.
    b.emit1(Opcode.pushConst, b.addConst(null)); // initial last-result
    final loopTop = b.currentAddr;
    _compile(node.children[0], b); // condition
    final exitJump = b.emitJump(Opcode.jumpFalse);

    b.emit(Opcode.pop); // discard last-result before body

    _loopStack.add((breaks: [], continues: [], continueAddr: loopTop));
    _compile(node.children[1], b); // body — result stays on stack
    final ctx = _loopStack.removeLast();

    b.emit1(Opcode.jump, loopTop);
    b.patchJump(exitJump);
    for (final idx in ctx.breaks) {
      b.patchJump(idx);
    }
    // last-result (null or last body value) is already on stack
  }

  // ---- REPEAT/UNTIL --------------------------------------------------------

  void _compileRepeatUntil(ParseTree node, ChunkBuilder b) {
    // children: [body, condition]
    //
    // Same stack discipline as WHILE: one "last result" slot maintained.
    //   push null            ← initial last-result (for BREAK before first body)
    //   .loopTop:
    //     pop                ← discard last-result; stack empty
    //     <body>             ← [body-result]
    //     condition          ← [body-result, condition]
    //     jumpTrue .exit     ← pops condition; if true → .exit with [body-result]
    //     jump .loopTop      ← condition false; [body-result] becomes new last-result
    //   .exit:               ← [body-result] on stack
    //
    // BREAK/CONTINUE: fire at statement boundaries (inside body, after pop).
    // Stack is empty — push null before jumping to restore balance.
    b.emit1(Opcode.pushConst, b.addConst(null)); // initial last-result
    final loopTop = b.currentAddr;
    b.emit(Opcode.pop); // discard last-result before body

    _loopStack.add((breaks: [], continues: [], continueAddr: loopTop));
    _compile(node.children[0], b); // body — result stays on stack
    final ctx = _loopStack.removeLast();

    _compile(node.children[1], b); // UNTIL condition → [body-result, condition]
    final exitJump = b.emitJump(Opcode.jumpTrue); // pops condition; if true → exit
    b.emit1(Opcode.jump, loopTop); // condition false → loop ([body-result] popped at loopTop)

    b.patchJump(exitJump); // .exit: body-result on stack
    for (final idx in ctx.breaks) {
      b.patchJump(idx);
    }
    // body-result (or null for BREAK exits) is on stack
  }

  // ---- FOR -----------------------------------------------------------------
  //
  // Compiled as a WHILE expansion matching ForLoopExecutionNode exactly:
  //   body-first, dynamic direction (target >= start_value), re-evaluated
  //   target/step per iteration, and — crucially — the loop variable is only
  //   updated when the next value does NOT overshoot the target.
  //
  //   i        := init
  //   r_sv     := i              -- start_value: initial i, fixes direction
  //   r_fin    := false          -- finished flag (exact hit last iter)
  //   .loop:
  //     <body>; pop
  //     if r_fin → exit          -- done from last iteration (exact hit)
  //     r_tgt  := <limit_expr>  -- re-evaluate target
  //     r_up   := r_tgt >= r_sv -- direction (>= matches ForLoopExecutionNode)
  //     r_step := step_expr     -- or (r_up ? 1 : -1)
  //     r_next := i + r_step    -- candidate next i (not stored yet)
  //     r_over := (r_up ∧ r_next>r_tgt) ∨ (¬r_up ∧ r_next<r_tgt)
  //     r_fin  := r_over ∨ r_next=r_tgt
  //     if r_over → exit        -- overshoot: skip update, skip final body
  //     i := r_next             -- only update when not overshooting
  //     jump .loop
  //   .exit:
  //   null                       -- FOR result

  void _compileFor(ParseTree node, ChunkBuilder b) {
    // Parser order: [initAssignment, bodyExpr, limitExpr, ?stepExpr]
    final hasStep   = node.children.length > 3;
    final initNode  = node.children[0];
    final bodyNode  = node.children[1];
    final limitNode = node.children[2];
    final stepNode  = hasStep ? node.children[3] : null;

    final loopVarName =
        _cs.identifiers.getByIndex(initNode.children[0].qualifier!)!;

    // Seven dedicated registers — nested FORs get higher indices.
    final rSv   = b.allocReg(); // start_value
    final rFin  = b.allocReg(); // finished flag
    final rTgt  = b.allocReg(); // target (re-evaluated each iteration)
    final rUp   = b.allocReg(); // counting_upwards = target >= start_value
    final rStep = b.allocReg(); // step value
    final rNext = b.allocReg(); // candidate next i (before updating i)
    final rOver = b.allocReg(); // overshoot flag

    // Init: i := start
    _compile(initNode, b);
    b.emit(Opcode.pop);

    // r_sv = initial i
    b.emit1(Opcode.loadVar, b.addName(loopVarName));
    b.emit1(Opcode.storeReg, rSv);

    // r_fin = false
    b.emit1(Opcode.pushConst, b.addConst(false));
    b.emit1(Opcode.storeReg, rFin);

    final loopTop = b.currentAddr;

    // Body — CONTINUE forward-fixups collected here, patched below.
    _loopStack.add((breaks: [], continues: [], continueAddr: -1));
    _compile(bodyNode, b);
    b.emit(Opcode.pop);
    final ctx = _loopStack.removeLast();

    // Continue target: the check/increment section right after the body.
    final contAddr = b.currentAddr;
    for (final idx in ctx.continues) b.patchAt(idx, contAddr);

    // if r_fin (reached target exactly last iteration) → exit
    b.emit1(Opcode.loadReg, rFin);
    final finBreak = b.emitJump(Opcode.jumpTrue);

    // r_tgt = re-evaluate limit
    _compile(limitNode, b);
    b.emit1(Opcode.storeReg, rTgt);

    // r_up = target >= start_value  (matches ForLoopExecutionNode: >= not >)
    b.emit1(Opcode.loadReg, rTgt);
    b.emit1(Opcode.loadReg, rSv);
    b.emit(Opcode.cmpGte);  // ← >= (was cmpGt)
    b.emit1(Opcode.storeReg, rUp);

    // r_step = step expression, or 1/-1 based on direction
    if (hasStep) {
      _compile(stepNode!, b);
      b.emit1(Opcode.storeReg, rStep);
    } else {
      b.emit1(Opcode.loadReg, rUp);
      final toNeg = b.emitJump(Opcode.jumpFalse);
      b.emit1(Opcode.pushConst, b.addConst(1));
      final stepDone = b.emitJump(Opcode.jump);
      b.patchJump(toNeg);
      b.emit1(Opcode.pushConst, b.addConst(-1));
      b.patchJump(stepDone);
      b.emit1(Opcode.storeReg, rStep);
    }

    // r_next = i + step  (candidate; i not updated yet)
    b.emit1(Opcode.loadVar, b.addName(loopVarName));
    b.emit1(Opcode.loadReg, rStep);
    b.emit(Opcode.add);
    b.emit1(Opcode.storeReg, rNext);

    // r_over = (r_up ∧ r_next > r_tgt) ∨ (¬r_up ∧ r_next < r_tgt)
    b.emit1(Opcode.loadReg, rUp);
    b.emit1(Opcode.loadReg, rNext);
    b.emit1(Opcode.loadReg, rTgt);
    b.emit(Opcode.cmpGt);
    b.emit(Opcode.logAnd);                 // r_up ∧ r_next>r_tgt
    b.emit1(Opcode.loadReg, rUp);
    b.emit(Opcode.logNot);                 // ¬r_up
    b.emit1(Opcode.loadReg, rNext);
    b.emit1(Opcode.loadReg, rTgt);
    b.emit(Opcode.cmpLt);
    b.emit(Opcode.logAnd);                 // ¬r_up ∧ r_next<r_tgt
    b.emit(Opcode.logOr);                  // overshoot
    b.emit1(Opcode.storeReg, rOver);

    // r_fin = r_over ∨ r_next = r_tgt
    b.emit1(Opcode.loadReg, rOver);
    b.emit1(Opcode.loadReg, rNext);
    b.emit1(Opcode.loadReg, rTgt);
    b.emit(Opcode.cmpEq);
    b.emit(Opcode.logOr);
    b.emit1(Opcode.storeReg, rFin);

    // if r_over → exit immediately (overshoot: skip i update, skip final body)
    b.emit1(Opcode.loadReg, rOver);
    final overBreak = b.emitJump(Opcode.jumpTrue);

    // i := r_next  (only when not overshooting)
    b.emit1(Opcode.loadReg, rNext);
    b.emit1(Opcode.storeVar, b.addName(loopVarName));

    b.emit1(Opcode.jump, loopTop);

    // Exit: patch all exits (internal + user BREAKs) to here
    b.patchAt(finBreak, b.currentAddr);
    b.patchAt(overBreak, b.currentAddr);
    for (final idx in ctx.breaks) b.patchJump(idx);

    b.emit1(Opcode.pushConst, b.addConst(null));
  }

  // ---- RETURN --------------------------------------------------------------

  void _compileReturn(ParseTree node, ChunkBuilder b) {
    if (node.children.isNotEmpty) {
      _compile(node.children[0], b);
    } else {
      b.emit1(Opcode.pushConst, b.addConst(null));
    }
    b.emit(Opcode.ret);
  }

  // ---- BREAK / CONTINUE ----------------------------------------------------

  void _compileBreak(ChunkBuilder b) {
    if (_loopStack.isEmpty) throw BytecodeCompileError('BREAK outside loop');
    final ctx = _loopStack.last;
    if (ctx.continueAddr >= 0) {
      // WHILE / REPEAT: the result-tracking structure pops last-result before body,
      // so the stack is empty at BREAK time. Push null so the exit finds its slot.
      b.emit1(Opcode.pushConst, b.addConst(null));
    }
    ctx.breaks.add(b.emitJump(Opcode.jump));
  }

  void _compileContinue(ChunkBuilder b) {
    if (_loopStack.isEmpty) throw BytecodeCompileError('CONTINUE outside loop');
    final ctx = _loopStack.last;
    if (ctx.continueAddr >= 0) {
      // WHILE / REPEAT: target is already known.
      // Stack is empty at CONTINUE time (last-result was popped before body).
      // Push null so the pop at loopTop finds its expected value.
      b.emit1(Opcode.pushConst, b.addConst(null));
      b.emit1(Opcode.jump, ctx.continueAddr);
    } else {
      // FOR: target (increment) not yet emitted — collect forward reference.
      ctx.continues.add(b.emitJump(Opcode.jump));
    }
  }

  // ---- CALL ----------------------------------------------------------------

  void _compileCall(ParseTree node, ChunkBuilder b) {
    // x[i] is parsed as call(x, list([i])) — square brackets → index access.
    if (node.children.length > 1 &&
        node.children[1].symbol == Symbols.list) {
      _compile(node.children[0], b);                // container
      _compile(node.children[1].children[0], b);    // index (single element)
      b.emit(Opcode.getIndex);
      return;
    }
    _compile(node.children[0], b); // callable
    int argCount = 0;
    if (node.children.length > 1) {
      argCount = _compileArgs(node.children[1], b);
    }
    b.emit1(Opcode.call, argCount);
  }

  int _compileArgs(ParseTree node, ChunkBuilder b) {
    if (node.symbol == Symbols.tuple) {
      for (final child in node.children) {
        _compile(child, b);
      }
      return node.children.length;
    }
    _compile(node, b);
    return 1;
  }

  // ---- LAMBDA --------------------------------------------------------------

  void _compileLambda(ParseTree node, ChunkBuilder b) {
    // children: [paramList, bodyExpr]
    final chunkName = _freshName('lambda');
    final params = <String>[];
    _collectParams(node.children[0], params);

    final fn = ChunkBuilder(chunkName, params);
    _compile(node.children[1], fn);
    fn.emit(Opcode.ret);
    _registerChunk(fn);

    b.emit1(Opcode.makeClosure, b.addConst(ChunkRef(chunkName)));
  }

  // ---- LIST ----------------------------------------------------------------

  void _compileList(ParseTree node, ChunkBuilder b) {
    for (final child in node.children) {
      _compile(child, b);
    }
    b.emit1(Opcode.makeList, node.children.length);
  }

  // ---- MAP -----------------------------------------------------------------

  void _compileMap(ParseTree node, ChunkBuilder b) {
    // Each child is a colon node: [key, value].
    // Produces a Dart Map (not a SHQL Object).
    for (final pair in node.children) {
      _compileMapKey(pair.children[0], b);
      _compile(pair.children[1], b);
    }
    b.emit1(Opcode.makeMap, node.children.length);
  }

  void _compileMapKey(ParseTree key, ChunkBuilder b) {
    if (key.symbol == Symbols.identifier) {
      // Identifier keys become their string name.
      b.emit1(
        Opcode.pushConst,
        b.addConst(_cs.identifiers.getByIndex(key.qualifier!)!),
      );
    } else {
      _compile(key, b);
    }
  }

  // ---- OBJECT LITERAL ------------------------------------------------------
  //
  // Object literal children come in three forms (matching ObjectLiteralNode):
  //   1. colon(identifier_key, value)       — simple key:value pair
  //   2. lambdaExpression(colon(key, params), body) — method definition
  //   3. assignment(lambdaExpression, rhs)  — method with assignment body
  //      (parser wraps lambda in assignment due to operator precedence when
  //       the method body is itself an assignment expression)

  void _compileObject(ParseTree node, ChunkBuilder b) {
    // pushScope creates Scope(newObject, parent=current).  Every make_closure
    // inside this block captures that scope, so closures hold a reference to
    // the same Object that makeObjectHere will populate.  By the time any
    // method is called, ALL fields (even those defined after the closure) are
    // visible through the captured scope — matching ObjectLiteralNode semantics.
    b.emit(Opcode.pushScope);

    var pairCount = 0;
    for (final child in node.children) {
      if (child.symbol == Symbols.colon) {
        _compileMapKey(child.children[0], b);
        _compile(child.children[1], b);
        pairCount++;
      } else if (child.symbol == Symbols.lambdaExpression) {
        // colon is children[0]; identifier key is colon.children[0]
        final colonNode = child.children[0];
        _compileMapKey(colonNode.children[0], b);
        _compileLambdaFromParts(colonNode.children[1], child.children[1], b);
        pairCount++;
      } else if (child.symbol == Symbols.assignment &&
                 child.children[0].symbol == Symbols.lambdaExpression) {
        // assignment wrapping lambda — rebuild the body as an assignment
        final lambdaNode  = child.children[0];
        final colonNode   = lambdaNode.children[0];
        final partialBody = lambdaNode.children[1]; // premature body from parser
        final actualRhs   = child.children[1];
        final fullBody    = ParseTree.withChildren(
          Symbols.assignment, [partialBody, actualRhs], child.tokens,
          sourceCode: child.sourceCode,
        );
        _compileMapKey(colonNode.children[0], b);
        _compileLambdaFromParts(colonNode.children[1], fullBody, b);
        pairCount++;
      } else {
        throw BytecodeCompileError(
          'Object literal: unexpected child ${child.symbol}',
        );
      }
    }

    // makeObjectHere reuses the pushScope Object, populating it with all pairs.
    // popScope restores the enclosing scope; closures retain their captured ref.
    b.emit1(Opcode.makeObjectHere, pairCount);
    b.emit(Opcode.popScope);
  }

  /// Compile a lambda given separate param-tree and body-tree nodes.
  /// Used by [_compileObject] to handle method definitions.
  void _compileLambdaFromParts(
    ParseTree paramsNode,
    ParseTree bodyNode,
    ChunkBuilder b,
  ) {
    final chunkName = _freshName('lambda');
    final params = <String>[];
    _collectParams(paramsNode, params);

    final fn = ChunkBuilder(chunkName, params);
    _compile(bodyNode, fn);
    fn.emit(Opcode.ret);
    _registerChunk(fn);

    b.emit1(Opcode.makeClosure, b.addConst(ChunkRef(chunkName)));
  }

  // ---- MEMBER ACCESS -------------------------------------------------------

  void _compileMemberAccess(ParseTree node, ChunkBuilder b) {
    // children: [objectExpr, identifierOrCall]
    _compile(node.children[0], b);

    final right = node.children[1];
    if (right.symbol == Symbols.identifier) {
      final name = _cs.identifiers.getByIndex(right.qualifier!)!;
      b.emit1(Opcode.getMember, b.addName(name));
    } else if (right.symbol == Symbols.call) {
      // Method call: obj.method(args)
      final methodId = right.children[0];
      if (methodId.symbol != Symbols.identifier) {
        throw BytecodeCompileError(
          'Method call: expected identifier, got ${methodId.symbol}',
        );
      }
      final name = _cs.identifiers.getByIndex(methodId.qualifier!)!;
      b.emit1(Opcode.getMember, b.addName(name));
      int argCount = 0;
      if (right.children.length > 1) {
        argCount = _compileArgs(right.children[1], b);
      }
      b.emit1(Opcode.call, argCount);
    } else {
      throw BytecodeCompileError(
        'Member access: unexpected RHS ${right.symbol}',
      );
    }
  }
}
