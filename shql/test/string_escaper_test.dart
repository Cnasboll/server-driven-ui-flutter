import 'package:test/test.dart';
import 'package:shql/tokenizer/string_escaper.dart';

void main() {
  group('StringEscaper.escape', () {
    test('plain ASCII text is preserved verbatim', () {
      expect(StringEscaper.escape('batman'), equals('batman'));
    });

    test('text with spaces is preserved', () {
      expect(StringEscaper.escape('hello world'), equals('hello world'));
    });

    test('double quotes are escaped', () {
      expect(StringEscaper.escape('name ~ "man"'), equals('name ~ \\"man\\"'));
    });

    test('backslashes are escaped', () {
      expect(StringEscaper.escape(r'a\b'), equals(r'a\\b'));
    });

    test('tabs are escaped', () {
      expect(StringEscaper.escape('a\tb'), equals('a\\tb'));
    });

    test('newlines are escaped', () {
      expect(StringEscaper.escape('a\nb'), equals('a\\nb'));
    });

    test('null returns empty string', () {
      expect(StringEscaper.escape(null), equals(''));
    });

    test('empty string returns empty string', () {
      expect(StringEscaper.escape(''), equals(''));
    });
  });
}
