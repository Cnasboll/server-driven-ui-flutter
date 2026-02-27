import 'dart:math';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:shql/engine/cancellation_token.dart';
import 'package:shql/execution/execution_node.dart';
import 'package:shql/execution/runtime/execution_context.dart';
import 'package:shql/execution/runtime_error.dart';
import 'package:shql/parser/constants_set.dart';
import 'package:shql/parser/parse_tree.dart';

class Callable {
  final String name;
  final int? identifier;

  Callable({required this.name, required this.identifier});
}

/// Represents a user-defined function with its arguments and body.
class UserFunction extends Callable {
  final List<int> argumentIdentifiers;
  final Scope scope;
  final ParseTree body;

  UserFunction({
    required super.name,
    required super.identifier,
    required this.argumentIdentifiers,
    required this.scope,
    required this.body,
  });
}

class NullaryFunction extends Callable {
  final Function(ExecutionContext executionContext, ExecutionNode caller)
  function;

  NullaryFunction({
    required super.name,
    required super.identifier,
    required this.function,
  });
}

class UnaryFunction extends Callable {
  final Function(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic p1,
  )
  function;

  UnaryFunction({
    required super.name,
    required super.identifier,
    required this.function,
  });
}

class BinaryFunction extends Callable {
  final Function(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic p1,
    dynamic p2,
  )
  function;

  BinaryFunction({
    required super.name,
    required super.identifier,
    required this.function,
  });
}

class TernaryFunction extends Callable {
  final Function(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic p1,
    dynamic p2,
    dynamic p3,
  )
  function;

  TernaryFunction({
    required super.name,
    required super.identifier,
    required this.function,
  });
}

class Constant {
  final dynamic value;
  final int identifier;

  Constant(this.value, this.identifier);
}

/// Wrapper class to distinguish between "variable not defined" and "variable is null"
class Variable {
  final dynamic value;

  Variable(this.value);
}

class Object {
  final Map<int, dynamic> members = {}; // Contains Variable or UserFunction
  final Map<int, Variable> variables = {};
  final Map<int, UserFunction> userFunctons = {};

  dynamic resolveIdentifier(int identifier) {
    return members[identifier];
  }

  bool hasMember(int identifier) {
    return members.containsKey(identifier);
  }

  void setVariable(int identifier, dynamic value) {
    var variable = Variable(value);
    members[identifier] = variable;
    variables[identifier] = variable;
    userFunctons.remove(identifier);
  }

  UserFunction defineUserFunction(int identifier, UserFunction userFunction) {
    members[identifier] = userFunction;
    userFunctons[identifier] = userFunction;
    variables.remove(identifier);
    return userFunction;
  }

  Object clone() {
    var newObject = Object();
    newObject.members.addAll(members);
    newObject.variables.addAll(variables);
    newObject.userFunctons.addAll(userFunctons);
    return newObject;
  }
}

class Scope {
  Object members;
  ConstantsTable<dynamic>? constants;
  Scope? parent;
  Scope(this.members, {this.constants, this.parent});

  (dynamic, Scope?, bool) resolveIdentifier(int identifier) {
    Scope? current = this;
    while (current != null) {
      var member = current.members.resolveIdentifier(identifier);
      if (member != null) {
        return (member, current, false);
      }
      current = current.parent;
    }

    if (constants != null) {
      var (value, index) = constants!.getByIdentifier(identifier);
      if (index != null) {
        return (value, this, true);
      }
    }

    return (null, null, false);
  }

  bool hasMember(int identifier) {
    Scope? current = this;
    while (current != null) {
      if (current.members.hasMember(identifier)) {
        return true;
      }
      current = current.parent;
    }

    if (constants != null) {
      var (value, index) = constants!.getByIdentifier(identifier);
      return index != null;
    }
    return false;
  }

  (Scope, RuntimeError?) setVariable(int identifier, dynamic value) {
    var (existingValue, containingScope, isConstant) = resolveIdentifier(
      identifier,
    );
    if (isConstant) {
      // Cannot modify constant
      return (containingScope!, RuntimeError("Cannot modify constant"));
    }
    containingScope ??= this;
    containingScope.members.setVariable(identifier, value);
    return (containingScope, null);
  }

  (Scope, UserFunction, RuntimeError?) defineUserFunction(
    int identifier,
    UserFunction userFunction,
  ) {
    var (existingValue, containingScope, isConstant) = resolveIdentifier(
      identifier,
    );
    if (isConstant) {
      // Cannot modify constant
      return (
        containingScope!,
        userFunction,
        RuntimeError("Cannot shadow constant with function"),
      );
    }

    containingScope ??= this;
    return (
      containingScope,
      containingScope.members.defineUserFunction(identifier, userFunction),
      null,
    );
  }

  Scope clone() {
    Scope? current = this;
    Scope? tail;
    Scope? head;
    while (current != null) {
      var newNode = Scope(
        current.members.clone(),
        constants: current.constants,
      );
      if (head == null) {
        head = tail = newNode;
      } else {
        tail!.parent = newNode;
        tail = newNode;
      }
      current = current.parent;
    }
    return head!;
  }
}

enum BreakState { none, breaked, continued }

class BreakTarget {
  BreakState _state = BreakState.none;
  void breakExecution() {
    _state = BreakState.breaked;
  }

  void continueExecution() {
    _state = BreakState.continued;
  }

  bool clearContinued() {
    var continued = _state == BreakState.continued;
    if (continued) {
      _state = BreakState.none;
    }
    return continued;
  }

  bool check(CancellationToken? cancellationToken) {
    if (cancellationToken?.isCancelled ?? false) {
      return true;
    }
    return _state == BreakState.breaked;
  }
}

class ReturnTarget {
  bool _returned = false;
  bool _hasReturnValue = false;

  dynamic _returnValue;

  dynamic get returnValue => _returnValue;
  bool get hasReturnValue => _hasReturnValue;

  void returnNothing() {
    _returned = true;
    _hasReturnValue = false;
    _returnValue = null;
  }

  void returnAValue(dynamic returnValue) {
    _returned = true;
    _hasReturnValue = true;
    _returnValue = returnValue;
  }

  bool check(CancellationToken? cancellationToken) {
    if (cancellationToken?.isCancelled ?? false) {
      return true;
    }
    return _returned;
  }
}

class Thread {
  final int id;
  final List<ExecutionNode> executionStack = [];
  final List<BreakTarget> _breakTargets = [];
  final List<ReturnTarget> _returnTargets = [];

  Future<bool>? _pendingOperation;
  bool _isOperationPending = false;

  Thread({required this.id});
  bool get isIdle => executionStack.isEmpty && !_isOperationPending;
  bool get isRunning => executionStack.isNotEmpty;
  ExecutionNode? get currentNode => isRunning ? executionStack.last : null;

  ExecutionNode? popNode() {
    if (isRunning) {
      return executionStack.removeLast();
    }
    return null;
  }

  ExecutionNode? onExecutionNodeComplete(ExecutionNode executionNode) {
    if (isRunning) {
      error ??= executionNode.error;
      result = executionNode.result;
      return popNode();
    }
    return null;
  }

  void pushNode(ExecutionNode executionNode) {
    executionStack.add(executionNode);
  }

  void reset() {
    error = null;
    result = null;
    clearExecutionStack();
    clearBreakTargets();
    clearReturnTargets();
  }

  void clearExecutionStack() {
    executionStack.clear();
  }

  BreakTarget pushBreakTarget() {
    var breakTarget = BreakTarget();
    _breakTargets.add(breakTarget);
    return breakTarget;
  }

  void popBreakTarget() {
    if (_breakTargets.isNotEmpty) {
      _breakTargets.removeLast();
    }
  }

  void breakCurrentExecution() {
    if (_breakTargets.isNotEmpty) {
      _breakTargets.last.breakExecution();
    }
  }

  BreakTarget? get currentBreakTarget {
    if (_breakTargets.isNotEmpty) {
      return _breakTargets.last;
    }
    return null;
  }

  BreakState currentExecutionBreakState() {
    if (_breakTargets.isNotEmpty) {
      return _breakTargets.last._state;
    }
    return BreakState.none;
  }

  void clearBreakTargets() {
    _breakTargets.clear();
  }

  (ReturnTarget?, RuntimeError?) pushReturnTarget() {
    if (_returnTargets.length >= 10) {
      return (
        null,
        RuntimeError(
          'Stack overflow. Too many nested function calls. 10 is the reasonable, chronological maximum allowed for a steam driven computing machine.',
        ),
      );
    }
    var returnTarget = ReturnTarget();
    _returnTargets.add(returnTarget);
    return (returnTarget, null);
  }

  void popReturnTarget() {
    if (_returnTargets.isNotEmpty) {
      _returnTargets.removeLast();
    }
  }

  ReturnTarget? get currentReturnTarget {
    if (_returnTargets.isNotEmpty) {
      return _returnTargets.last;
    }
    return null;
  }

  bool currentFunctionReturned() {
    if (_returnTargets.isNotEmpty) {
      return _returnTargets.last._returned;
    }
    return false;
  }

  void clearReturnTargets() {
    _returnTargets.clear();
  }

  bool check(CancellationToken? cancellationToken) {
    if (cancellationToken?.isCancelled ?? false) {
      return true;
    }
    if (currentExecutionBreakState() != BreakState.none) {
      return true;
    }
    return currentFunctionReturned();
  }

  Future<bool> tick(
    ExecutionContext executionContext, [
    CancellationToken? cancellationToken,
  ]) async {
    if (_pendingOperation != null && _isOperationPending) {
      return _pendingOperation!;
    }

    _isOperationPending = true;
    _pendingOperation = _tick(executionContext, cancellationToken).then((
      value,
    ) {
      _isOperationPending = false;
      return value;
    });
    return _pendingOperation!;
  }

  Future<bool> _tick(
    ExecutionContext executionContext, [
    CancellationToken? cancellationToken,
  ]) async {
    while ((cancellationToken == null || !cancellationToken.isCancelled)) {
      if (_joinTarget != null) {
        if (_joinTarget!.isRunning) {
          // Joined thread still running
          return false;
        }
        // Joined thread has completed
        _joinTarget = null;
        return true;
      }

      var currentNode = executionStack.isNotEmpty ? executionStack.last : null;
      if (currentNode == null) {
        return true;
      }
      var tickResult = await currentNode.tick(
        executionContext,
        cancellationToken,
      );
      if (tickResult == TickResult.iterated) {
        return false;
      }
    }
    return true;
  }

  void join(Thread joinTarget) {
    _joinTarget = joinTarget;
  }

  RuntimeError? error;
  dynamic result;
  dynamic getResult() {
    return result;
  }

  Thread? _joinTarget;
}

class Runtime {
  late final ConstantsTable<String> _identifiers;
  final Map<
    String,
    Function(ExecutionContext executionContext, ExecutionNode caller)
  >
  _nullaryFunctions = {};
  late final Map<
    int,
    Function(
      ExecutionContext executionContext,
      ExecutionNode caller,
      dynamic p1,
    )
  >
  _unaryFunctions;
  late final Map<
    int,
    Function(
      ExecutionContext executionContext,
      ExecutionNode caller,
      dynamic p1,
      dynamic p2,
    )
  >
  _binaryFunctions;
  late final Map<
    int,
    Function(
      ExecutionContext executionContext,
      ExecutionNode caller,
      dynamic p1,
      dynamic p2,
      dynamic p3,
    )
  >
  _ternaryFunctions;
  late final Scope globalScope;
  final Map<int, Runtime> _subModelScopes = {};
  bool _sandboxed = false;

  Function(dynamic value)? printFunction;
  Future<String?> Function()? readlineFunction;
  Future<String?> Function(String prompt)? promptFunction;
  Future<void> Function(String routeName)? navigateFunction;
  Future<dynamic> Function(String url)? fetchFunction;
  Future<dynamic> Function(String url, dynamic body)? postFunction;
  Future<dynamic> Function(String url, dynamic body)? patchFunction;
  Future<dynamic> Function(String url, String token)? fetchAuthFunction;
  Future<dynamic> Function(String url, dynamic body, String token)? patchAuthFunction;
  Future<void> Function(String key, dynamic value)? saveStateFunction;
  Future<dynamic> Function(String key, dynamic defaultValue)? loadStateFunction;
  Future<void> Function()? clsFunction;
  Future<void> Function()? hideGraphFunction;
  Future<void> Function(dynamic, dynamic)? plotFunction;
  Function(String message)? debugLogFunction;
  void Function(String name)? notifyListeners;

  Runtime({
    ConstantsSet? constantsSet,
    required Map<int, Function(dynamic p1)> unaryFunctions,
    required Map<int, Function(dynamic p1, dynamic p2)> binaryFunctions,
    required Map<int, Function(dynamic p1, dynamic p2, dynamic p3)>
    ternaryFunctions,
  }) {
    _identifiers = constantsSet?.identifiers ?? ConstantsTable();
    _unaryFunctions = Map.from(unaryFunctions);
    _binaryFunctions = Map.from(binaryFunctions);
    _ternaryFunctions = Map.from(ternaryFunctions);
    globalScope = Scope(
      Object(),
      constants: constantsSet?.constants ?? ConstantsTable(),
    );
    hookUpConsole();
  }

  Runtime._sandbox(Runtime other) {
    _identifiers = other._identifiers;
    _nullaryFunctions.addAll(other._nullaryFunctions);
    _unaryFunctions = Map.from(other._unaryFunctions);
    _binaryFunctions = Map.from(other._binaryFunctions);
    _ternaryFunctions = Map.from(other._ternaryFunctions);
    globalScope = other.globalScope.clone();
    _subModelScopes.addAll(other._subModelScopes);
    printFunction = other.printFunction;
    readlineFunction = other.readlineFunction;
    promptFunction = other.promptFunction;
    navigateFunction = other.navigateFunction;
    fetchFunction = other.fetchFunction;
    postFunction = other.postFunction;
    patchFunction = other.patchFunction;
    fetchAuthFunction = other.fetchAuthFunction;
    patchAuthFunction = other.patchAuthFunction;
    saveStateFunction = other.saveStateFunction;
    loadStateFunction = other.loadStateFunction;
    clsFunction = other.clsFunction;
    hideGraphFunction = other.hideGraphFunction;
    plotFunction = other.plotFunction;
    debugLogFunction = other.debugLogFunction;
    notifyListeners = other.notifyListeners;
    hookUpConsole();
    _sandboxed = true;
  }

  Runtime._subModel(Runtime parent) {
    globalScope = Scope(Object(), constants: parent.globalScope.constants);
    _identifiers = parent._identifiers;
    // Sub-models have their own global scope
  }

  ConstantsTable<String> get identifiers {
    return _identifiers;
  }

  Runtime sandbox() {
    final child = Runtime._sandbox(this);
    return child;
  }

  Runtime getSubModelScope(int identifier) {
    var scope = _subModelScopes[identifier];
    scope ??= _subModelScopes[identifier] = Runtime._subModel(this);
    return scope;
  }

  bool hasNullaryFunction(String name) {
    return _nullaryFunctions.containsKey(name);
  }

  Function(ExecutionContext executionContext, ExecutionNode caller)?
  getNullaryFunction(String name) {
    return _nullaryFunctions[name];
  }

  void setNullaryFunction(
    String name,
    dynamic Function(ExecutionContext executionContext, ExecutionNode caller)
    nullaryFunction,
  ) {
    _nullaryFunctions[name] = nullaryFunction;
  }

  bool hasUnaryFunction(int identifier) {
    return _unaryFunctions.containsKey(identifier);
  }

  Function(ExecutionContext executionContext, ExecutionNode caller, dynamic p1)?
  getUnaryFunction(int identifier) {
    return _unaryFunctions[identifier];
  }

  void setUnaryFunction(
    String name,
    dynamic Function(
      ExecutionContext executionContext,
      ExecutionNode caller,
      dynamic p1,
    )
    unaryFunction,
  ) {
    _unaryFunctions[identifiers.include(name)] = unaryFunction;
  }

  Function(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic p1,
    dynamic p2,
  )?
  getBinaryFunction(int identifier) {
    return _binaryFunctions[identifier];
  }

  bool hasBinaryFunction(int identifier) {
    return _binaryFunctions.containsKey(identifier);
  }

  void setBinaryFunction(
    String name,
    dynamic Function(
      ExecutionContext executionContext,
      ExecutionNode caller,
      dynamic p1,
      dynamic p2,
    )
    binaryFunction,
  ) {
    _binaryFunctions[identifiers.include(name)] = binaryFunction;
  }

  Function(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic p1,
    dynamic p2,
    dynamic p3,
  )?
  getTernaryFunction(int identifier) {
    return _ternaryFunctions[identifier];
  }

  bool hasTernaryFunction(int identifier) {
    return _ternaryFunctions.containsKey(identifier);
  }

  void setTernaryFunction(
    String name,
    dynamic Function(
      ExecutionContext executionContext,
      ExecutionNode caller,
      dynamic p1,
      dynamic p2,
      dynamic p3,
    )
    ternaryFunction,
  ) {
    _ternaryFunctions[identifiers.include(name)] = ternaryFunction;
  }

  void print(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic value,
  ) {
    if (sandboxed) {
      return;
    }

    printFunction?.call(value);
  }

  Future<String> prompt(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic prompt,
  ) async {
    if (sandboxed) {
      return "";
    }

    return await promptFunction?.call(prompt) ?? "";
  }

  Future<void> navigate(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic routeName,
  ) async {
    if (sandboxed) {
      return;
    }

    return await navigateFunction?.call(routeName);
  }

  Future<dynamic> fetch(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic url,
  ) async {
    if (sandboxed) {
      return;
    }

    return fetchFunction?.call(url);
  }

  Future<dynamic> post(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic url,
    dynamic body,
  ) async {
    if (sandboxed) {
      return;
    }

    return postFunction?.call(url, body);
  }

  Future<dynamic> patch(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic url,
    dynamic body,
  ) async {
    if (sandboxed) {
      return;
    }

    return patchFunction?.call(url, body);
  }

  Future<dynamic> fetchAuth(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic url,
    dynamic token,
  ) async {
    if (sandboxed) {
      return;
    }

    return fetchAuthFunction?.call(url, token);
  }

  Future<dynamic> patchAuth(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic url,
    dynamic body,
    dynamic token,
  ) async {
    if (sandboxed) {
      return;
    }

    return patchAuthFunction?.call(url, body, token);
  }

  Future<String> readLine(
    ExecutionContext executionContext,
    ExecutionNode caller,
  ) async {
    if (sandboxed) {
      return "";
    }

    return await readlineFunction?.call() ?? "";
  }

  Future<void> plot(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic xVector,
    dynamic yVector,
  ) async {
    if (sandboxed) {
      return;
    }
    await plotFunction?.call(xVector, yVector);
  }

  Future<void> set(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic name,
    dynamic value,
  ) async {
    if (sandboxed) {
      return;
    }

    caller.scope.setVariable(identifiers.include(name.toUpperCase()), value);
    notifyListeners?.call(name);
  }

  Future<void> saveState(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic key,
    dynamic value,
  ) async {
    if (sandboxed) {
      return;
    }

    await saveStateFunction?.call(key, value);
  }

  Future<dynamic> loadState(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic key,
    dynamic defaultValue,
  ) async {
    if (sandboxed) {
      return;
    }

    return loadStateFunction?.call(key, defaultValue);
  }

  Future<void> cls(
    ExecutionContext executionContext,
    ExecutionNode caller,
  ) async {
    if (sandboxed) {
      return;
    }

    await clsFunction?.call();
  }

  Future<void> hideGraph(
    ExecutionContext executionContext,
    ExecutionNode caller,
  ) async {
    if (sandboxed) {
      return;
    }

    await hideGraphFunction?.call();
  }

  void debugLog(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic message,
  ) {
    if (sandboxed) {
      return;
    }

    debugLogFunction?.call(message.toString());
  }

  Future<Thread> startThread(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic userFunction,
  ) async {
    return executionContext.startThread(caller, userFunction);
  }

  void joinThread(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic thread,
  ) {
    if (sandboxed) {
      return;
    }

    caller.thread.join(thread);
  }

  dynamic extern(
    ExecutionContext executionContext,
    ExecutionNode caller,
    dynamic name,
    dynamic args,
  ) {
    var unaryFunction = unaryFunctions[name];
    if (unaryFunction != null) {
      if (args is List && args.length == 1) {
        return unaryFunction(caller, args[0]);
      }
    }
    var binaryFunction = binaryFunctions[name];
    if (binaryFunction != null) {
      if (args is List && args.length == 2) {
        return binaryFunction(args[0], args[1]);
      }
    }

    var ternaryFunction = ternaryFunctions[name];
    if (ternaryFunction != null) {
      if (args is List && args.length == 3) {
        return ternaryFunction(args[0], args[1], args[2]);
      }
    }
    return null;
  }

  void hookUpConsole() {
    setUnaryFunction("PRINT", print);
    setUnaryFunction("PROMPT", prompt);
    setUnaryFunction("NAVIGATE", navigate);
    setUnaryFunction("FETCH", fetch);
    setBinaryFunction("POST", post);
    setBinaryFunction("PATCH", patch);
    setBinaryFunction("FETCH_AUTH", fetchAuth);
    setTernaryFunction("PATCH_AUTH", patchAuth);
    setNullaryFunction("READLINE", readLine);
    setBinaryFunction("_DISPLAY_GRAPH", plot);
    setBinaryFunction("SET", set);
    setBinaryFunction("SAVE_STATE", saveState);
    setBinaryFunction("LOAD_STATE", loadState);
    setNullaryFunction("CLS", cls);
    setNullaryFunction("HIDE_GRAPH", hideGraph);
    setUnaryFunction("THREAD", startThread);
    setUnaryFunction("JOIN", joinThread);
    setUnaryFunction("DEBUG_LOG", debugLog);
    setBinaryFunction("_EXTERN", extern);
  }

  static ConstantsSet prepareConstantsSet() {
    var constantsSet = ConstantsSet();
    // Register mathematical constants
    for (var entry in allConstants.entries) {
      constantsSet.registerConstant(
        entry.value,
        constantsSet.includeIdentifier(entry.key),
      );
    }

    return constantsSet;
  }

  static Runtime prepareRuntime([ConstantsSet? constantsSet]) {
    constantsSet ??= prepareConstantsSet();
    final unaryFns = <int, Function(dynamic p1)>{};

    final binaryFns = <int, Function(dynamic p1, dynamic p2)>{};

    final ternaryFns = <int, Function(dynamic p1, dynamic p2, dynamic p3)>{};

    var runtime = Runtime(
      constantsSet: constantsSet,
      unaryFunctions: unaryFns,
      binaryFunctions: binaryFns,
      ternaryFunctions: ternaryFns,
    );
    return runtime;
  }

  static final Map<String, dynamic> allConstants = {
    "ANSWER": 42,
    "TRUE": true,
    "FALSE": false,
    "E": e,
    "LN10": ln10,
    "LN2": ln2,
    "LOG2E": log2e,
    "LOG10E": log10e,
    "PI": pi,
    "SQRT1_2": sqrt1_2,
    "SQRT2": sqrt2,
    "AVOGADRO": 6.0221408e+23,
  };

  static final Map<String, dynamic Function(ExecutionNode caller, dynamic)>
  unaryFunctions = {
    "CLONE": (caller, a) {
      if (a is Map) {
        return _deepCopyMap(a);
      }
      if (a is List) {
        return _deepCopy(a);
      }
      if (a is String) {
        return String.fromCharCodes(a.codeUnits);
      }
      if (a is Object) {
        return a.clone();
      }
      return a;
    },
    "MD5": (caller, a) => md5.convert(utf8.encode(a.toString())).toString(),
    "SIN": (caller, a) => sin(a),
    "COS": (caller, a) => cos(a),
    "TAN": (caller, a) => tan(a),
    "ACOS": (caller, a) => acos(a),
    "ASIN": (caller, a) => asin(a),
    "ATAN": (caller, a) => atan(a),
    "SQRT": (caller, a) => sqrt(a),
    "EXP": (caller, a) => exp(a),
    "LOG": (caller, a) => log(a),
    "LOWERCASE": (caller, a) => a.toString().toLowerCase(),
    "UPPERCASE": (caller, a) => a.toString().toUpperCase(),
    "TRIM": (caller, a) => a?.toString().trim(),
    "INT": (caller, a) {
      if (a is int) {
        return a;
      }
      if (a is String) {
        return int.tryParse(a) ?? 0;
      }
      if (a is double) {
        return a.toInt();
      }
      return a;
    },
    "DOUBLE": (caller, a) {
      if (a is double) {
        return a;
      }
      if (a is String) {
        return double.tryParse(a) ?? 0.0;
      }
      if (a is int) {
        return a.toDouble();
      }
      return a;
    },
    "STRING": (caller, a) => a.toString(),
    "ROUND": (caller, a) => a is double ? a.round() : a,
    "MAP_VALUES": (caller, a) => (a is Map) ? a.values.toList() : [],
    "LENGTH": (caller, a) {
      if (a is String) {
        return a.length;
      }
      if (a is List) {
        return a.length;
      }
      if (a is Map) {
        return a.length;
      }
      return 0;
    },
  };

  static dynamic _deepCopy(dynamic obj) {
    if (obj is Map) {
      return _deepCopyMap(obj);
    } else if (obj is List) {
      return obj.map((e) => _deepCopy(e)).toList();
    }
    return obj;
  }

  static Map<dynamic, dynamic> _deepCopyMap(Map<dynamic, dynamic> map) {
    final newMap = <dynamic, dynamic>{};
    map.forEach((key, value) {
      newMap[_deepCopy(key)] = _deepCopy(value);
    });
    return newMap;
  }

  static final Map<String, dynamic Function(dynamic, dynamic)> binaryFunctions =
      {
        "MIN": (a, b) => min(a, b),
        "MAX": (a, b) => max(a, b),
        "ATAN2": (a, b) => atan2(a, b),
        "POW": (a, b) => pow(a, b),
        "MAP_REMOVE": (a, b) {
          if (a is Map) a.remove(b);
          return a;
        },
        "DIM": (a, b) {
          if (a is List && b is num) {
            while (a.length > b) {
              a.removeLast();
            }
            while (a.length < b) {
              a.add(0);
            }
          }
          return a;
        },
      };

  static final Map<String, dynamic Function(dynamic, dynamic, dynamic)>
  ternaryFunctions = {
    "SUBSTRING": (a, start, end) {
      if (a is String && start is int && end is int) {
        return a.substring(start, end);
      }
      return a;
    },
  };

  bool get sandboxed => _sandboxed;
}
