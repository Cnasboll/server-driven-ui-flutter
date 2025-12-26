class ConstantsTable<T> {
  ConstantsTable({ConstantsTable<T>? parent}) : _parent = parent;

  // Deep copy constructor
  ConstantsTable.copy(ConstantsTable<T> other, {ConstantsTable<T>? parent})
    : _parent = parent {
    // Deep copy all the collections
    _constants.addAll(other._constants);
    _index.addAll(other._index);
    _indexByIdentifier.addAll(other._indexByIdentifier);
  }

  int include(T value) {
    var index = _index[value];

    if (index == null) {
      index = _index[value] = _constants.length;
      _constants.add(value);
    }
    return index;
  }

  int register(T value, int identifier) {
    var index = _index[value];

    if (index == null) {
      index = _index[value] = _constants.length;
      _constants.add(value);
    }
    _indexByIdentifier[identifier] = index;
    return index;
  }

  T? getByIndex(int index) {
    if (index < 0 || index >= _constants.length) {
      return null;
    }
    return _constants[index];
  }

  (T?, int?) getByIdentifier(int identifier) {
    var index = _indexByIdentifier[identifier];
    if (index == null) {
      if (_parent != null) {
        return _parent.getByIdentifier(identifier);
      }
      return (null, null);
    }
    return (_constants[index], index);
  }

  List<T> get constants {
    return _constants;
  }

  ConstantsTable<T>? root() {
    if (_parent == null) {
      return this;
    }

    return _parent.root();
  }

  final List<T> _constants = [];
  final Map<T, int> _index = {};
  final Map<int, int> _indexByIdentifier = {};
  final ConstantsTable<T>? _parent;
}

class ConstantsSet {
  ConstantsSet() : constants = ConstantsTable(), identifiers = ConstantsTable();

  ConstantsTable<dynamic> constants;
  ConstantsTable<String> identifiers;

  int includeConstant(dynamic value) => constants.include(value);
  int includeIdentifier(String name) => identifiers.include(name);

  int registerConstant(dynamic value, int identifier) =>
      constants.register(value, identifier);
  int registerIdentifier(String name, int identifier) =>
      identifiers.register(name, identifier);

  (dynamic, int?) getConstantByIdentifier(int identifier) =>
      constants.getByIdentifier(identifier);
  dynamic getConstantByIndex(int index) => constants.getByIndex(index);

  (String?, int?) getIdentifierByIndex(int index) =>
      (identifiers.constants[index], index);
}
