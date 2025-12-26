class StringEscaper {
  static String escape(String? unescaped) {
    if (unescaped == null || unescaped.isEmpty) {
      return "";
    }

    var sb = StringBuffer();

    for (var c in unescaped.runes) {
      var char = String.fromCharCode(c);
      switch (char) {
        case '\\':
          {
            sb.write("\\\\");
            break;
          }
        case '\t':
          sb.write("\\t");
          break;
        case '\n':
          sb.write("\\n");
          break;
        case '\f':
          sb.write("\\f");
          break;
        case '\r':
          sb.write("\\r");
          break;
        default:
          sb.write(c);
          break;
      }
    }

    return sb.toString();
  }

  static String unescape(String? escapedString) {
    if (escapedString == null || escapedString.isEmpty) {
      return "";
    }

    var sb = StringBuffer();
    for (int i = 1; i < escapedString.length - 1; ++i) {
      var ch = escapedString[i];
      if (ch == '\\') {
        ch = escapedString[++i];
        switch (ch) {
          case 'b':
            ch = '\b';
            break;
          case 't':
            ch = '\t';
            break;
          case 'n':
            ch = '\n';
            break;
          case 'f':
            ch = '\f';
            break;
          case 'r':
            ch = '\r';
            break;
        }
      }

      sb.write(ch);
    }
    return sb.toString();
  }
}
