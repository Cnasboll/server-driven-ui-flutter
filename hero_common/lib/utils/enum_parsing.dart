extension EnumParsing<T extends Enum> on Iterable<T> {
  T? findMatch(String s) {
    for (var v in this) {
      if (v.name.toLowerCase().startsWith(s.toLowerCase())) {
        return v;
      }
    }
    return null;
  }
   T? tryParse(String s) {
    for (var v in this) {
      if (v.name == s) {
        return v;
      }
    }
    return null;
  }
}

