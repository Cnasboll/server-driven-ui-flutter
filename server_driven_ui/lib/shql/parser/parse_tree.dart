import 'package:server_driven_ui/shql/tokenizer/token.dart';
import 'package:server_driven_ui/shql/tokenizer/code_span.dart';

class ParseTree {
  ParseTree(
    this._symbol,
    this._tokens, [
    this._children = const [],
    this._qualifier,
    this.sourceCode,
  ]);

  ParseTree.withSymbol(Symbols symbol, List<Token> tokens, {String? sourceCode})
    : this(symbol, tokens, const [], null, sourceCode);
  ParseTree.withChildren(
    Symbols symbol,
    List<ParseTree> children,
    List<Token> tokens, {
    String? sourceCode,
  }) : this(symbol, tokens, children, null, sourceCode);

  ParseTree.withQualifier(
    Symbols symbol,
    int? qualifier,
    List<Token> tokens, {
    String? sourceCode,
  }) : this(symbol, tokens, const [], qualifier, sourceCode);

  Symbols get symbol {
    return _symbol;
  }

  List<ParseTree> get children {
    return _children;
  }

  int? get qualifier {
    return _qualifier;
  }

  @override
  String toString() {
    var childrenToString = StringBuffer();
    for (var child in children) {
      childrenToString.write(child.toString());
    }
    return '$_symbol($childrenToString)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParseTree &&
          runtimeType == other.runtimeType &&
          _symbol == other._symbol &&
          _children == other._children &&
          _qualifier == other._qualifier;

  @override
  int get hashCode {
    return Object.hash(_symbol, _children, _qualifier);
  }

  List<Token> get tokens {
    return _tokens;
  }

  CodeSpan get tokenSpan => _tokens.isEmpty ? (null, null) : _tokens.tokenSpan;

  final Symbols _symbol;
  final List<ParseTree> _children;
  final int? _qualifier;
  final List<Token> _tokens;
  final String? sourceCode;
}
