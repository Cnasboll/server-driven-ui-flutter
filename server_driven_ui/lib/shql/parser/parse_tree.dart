import 'package:server_driven_ui/shql/tokenizer/token.dart';

class ParseTree {
  ParseTree(this._symbol, [this._children = const [], this._qualifier]);

  ParseTree.withSymbol(Symbols symbol) : this(symbol, const [], null);

  ParseTree.withChildren(Symbols symbol, List<ParseTree> children)
    : this(symbol, children, null);

  ParseTree.withQualifier(Symbols symbol, int? qualifier)
    : this(symbol, const [], qualifier);

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

  final Symbols _symbol;
  final List<ParseTree> _children;
  final int? _qualifier;
}
