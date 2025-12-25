import 'dart:convert';

String? specialNullCoalesce(
  Object? o, {
  List<String> extraNullLiterals = const [],
}) {
  if (o == null) {
    return null;
  }

  // So strings containing "null" or "-" are treated as null, little Bobby Dashes we call him
  var s = o is String ? o : o.toString();
  if (["null", "-", ...extraNullLiterals].contains(s)) {
    return null;
  }
  return s;
}

List<String>? getNullableStringListFromMap(
  Map<String, dynamic>? map,
  String key, {
  List<String> extraNullLiterals = const <String>[],
}) {
  var list = map?[key];
  if (list == null) {
    return null;
  }

  /// Special handler! if it is a json-encoded string, decode it
  if (list is String) {
    var s = specialNullCoalesce(list, extraNullLiterals: extraNullLiterals);
    if (s == null) {
      return null;
    }
    try {
      list = jsonDecode(s);
    } catch (e) {
      // Not JSON, return as single-item list
      return [list.toString()];
    }
  }

  if (list is String) {
    // Single string, return as single-item list
    return [list];
  }

  if (list is! List) {
    // Not a list, return as single-item list
    return [list.toString()];
  }

  // Handle [-] as null!
  if (list.length == 1) {
    var s = specialNullCoalesce(
      list.first,
      extraNullLiterals: extraNullLiterals,
    );
    if (s == null) {
      return null;
    }
  }
  
  if (list is! List<String>) {
    // Convert all items to strings
    return List<String>.from(list);
  }

  return list;
}
