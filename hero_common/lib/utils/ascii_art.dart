
/// Simple ASCII art converter for hero images
class AsciiArt {

  /// Create ASCII banner text
  static String createBanner(String text) {
    if (text.isEmpty) return '';

    final lines = List.generate(5, (_) => StringBuffer());

    for (final char in text.toUpperCase().runes) {
      final charStr = String.fromCharCode(char);
      final pattern = _getCharPattern(charStr);

      for (int i = 0; i < 5; i++) {
        lines[i].write(pattern[i]);
        if (char != text.toUpperCase().runes.last) {
          lines[i].write(' '); // Space between characters
        }
      }
    }

    return lines.map((line) => line.toString()).join('\n');
  }

  /// Get ASCII pattern for a character (complete font)
  static List<String> _getCharPattern(String char) {
    switch (char) {
      // Alphabet A-Z
      case 'A':
        return ['  ██  ', ' █  █ ', '██████', '█    █', '█    █'];
      case 'B':
        return ['█████ ', '█    █', '█████ ', '█    █', '█████ '];
      case 'C':
        return [' █████', '█     ', '█     ', '█     ', ' █████'];
      case 'D':
        return ['████  ', '█   █ ', '█    █', '█   █ ', '████  '];
      case 'E':
        return ['██████', '█     ', '█████ ', '█     ', '██████'];
      case 'F':
        return ['██████', '█     ', '█████ ', '█     ', '█     '];
      case 'G':
        return [' █████', '█     ', '█  ███', '█    █', ' █████'];
      case 'H':
        return ['█    █', '█    █', '██████', '█    █', '█    █'];
      case 'I':
        return ['██████', '  ██  ', '  ██  ', '  ██  ', '██████'];
      case 'J':
        return ['██████', '    █ ', '    █ ', '█   █ ', ' █████'];
      case 'K':
        return ['█   █ ', '█  █  ', '███   ', '█  █  ', '█   █ '];
      case 'L':
        return ['█     ', '█     ', '█     ', '█     ', '██████'];
      case 'M':
        return ['█    █', '██  ██', '█ ██ █', '█    █', '█    █'];
      case 'N':
        return ['█    █', '██   █', '█ █  █', '█  █ █', '█   ██'];
      case 'O':
        return [' █████', '█    █', '█    █', '█    █', ' █████'];
      case 'P':
        return ['█████ ', '█    █', '█████ ', '█     ', '█     '];
      case 'Q':
        return [' █████', '█    █', '█ █  █', '█  █ █', ' ██████'];
      case 'R':
        return ['█████ ', '█    █', '█████ ', '█   █ ', '█    █'];
      case 'S':
        return [' █████', '█     ', ' ████ ', '     █', '█████ '];
      case 'T':
        return ['██████', '  ██  ', '  ██  ', '  ██  ', '  ██  '];
      case 'U':
        return ['█    █', '█    █', '█    █', '█    █', ' █████'];
      case 'V':
        return ['█    █', '█    █', '█    █', ' █  █ ', '  ██  '];
      case 'W':
        return ['█    █', '█    █', '█ ██ █', '██  ██', '█    █'];
      case 'X':
        return ['█    █', ' █  █ ', '  ██  ', ' █  █ ', '█    █'];
      case 'Y':
        return ['█    █', ' █  █ ', '  ██  ', '  ██  ', '  ██  '];
      case 'Z':
        return ['██████', '    █ ', '   █  ', '  █   ', '██████'];

      // Numbers 0-9
      case '0':
        return [' █████', '█   █ ', '█ █ █ ', '█  █ █', ' █████'];
      case '1':
        return ['  ██  ', ' ███  ', '  ██  ', '  ██  ', '██████'];
      case '2':
        return [' █████', '█    █', '   ██ ', '  █   ', '██████'];
      case '3':
        return [' █████', '     █', '  ████', '     █', ' █████'];
      case '4':
        return ['█   █ ', '█   █ ', '██████', '    █ ', '    █ '];
      case '5':
        return ['██████', '█     ', '█████ ', '     █', '█████ '];
      case '6':
        return [' █████', '█     ', '█████ ', '█    █', ' █████'];
      case '7':
        return ['██████', '    █ ', '   █  ', '  █   ', ' █    '];
      case '8':
        return [' █████', '█    █', ' █████', '█    █', ' █████'];
      case '9':
        return [' █████', '█    █', ' ██████', '     █', ' █████'];

      // Common symbols
      case '!':
        return ['  ██  ', '  ██  ', '  ██  ', '      ', '  ██  '];
      case '?':
        return [' █████', '█    █', '   ██ ', '      ', '  ██  '];
      case '.':
        return ['      ', '      ', '      ', '      ', '  ██  '];
      case ',':
        return ['      ', '      ', '      ', '  ██  ', ' █    '];
      case ':':
        return ['      ', '  ██  ', '      ', '  ██  ', '      '];
      case ';':
        return ['      ', '  ██  ', '      ', '  ██  ', ' █    '];
      case '-':
        return ['      ', '      ', '██████', '      ', '      '];
      case '_':
        return ['      ', '      ', '      ', '      ', '██████'];
      case '(':
        return ['   ██ ', '  █   ', '  █   ', '  █   ', '   ██ '];
      case ')':
        return [' ██   ', '   █  ', '   █  ', '   █  ', ' ██   '];
      case '[':
        return ['████  ', '█     ', '█     ', '█     ', '████  '];
      case ']':
        return ['  ████', '     █', '     █', '     █', '  ████'];
      case '/':
        return ['     █', '    █ ', '   █  ', '  █   ', ' █    '];
      case '\\':
        return ['█     ', ' █    ', '  █   ', '   █  ', '    █ '];
      case '+':
        return ['      ', '  ██  ', '██████', '  ██  ', '      '];
      case '=':
        return ['      ', '██████', '      ', '██████', '      '];
      case '*':
        return ['      ', ' █ █ █', '  ███ ', ' █ █ █', '      '];
      case '#':
        return [' █ █  ', '██████', ' █ █  ', '██████', ' █ █  '];
      case '@':
        return [' █████', '█ ███ ', '█ █ █ ', '█ ███ ', ' █████'];
      case '&':
        return [' ███  ', '█   █ ', ' ███  ', '█ █ █ ', ' ███ █'];
      case '%':
        return ['██   █', '██  █ ', '   █  ', '  █ ██', ' █  ██'];
      case r'$':
        return ['  ██  ', ' █████', '██ ██ ', ' █████', '  ██  '];
      case '"':
        return [' █ █  ', ' █ █  ', '      ', '      ', '      '];
      case '\'':
        return ['  ██  ', '  ██  ', '      ', '      ', '      '];
      case '<':
        return ['    █ ', '   █  ', '  █   ', '   █  ', '    █ '];
      case '>':
        return [' █    ', '  █   ', '   █  ', '  █   ', ' █    '];
      case '|':
        return ['  ██  ', '  ██  ', '  ██  ', '  ██  ', '  ██  '];

      // Space
      case ' ':
        return ['      ', '      ', '      ', '      ', '      '];

      // Default fallback for unknown characters
      default:
        return ['██████', '█    █', '█ ?? █', '█    █', '██████'];
    }
  }
}
