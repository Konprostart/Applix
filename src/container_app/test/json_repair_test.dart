import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:applix/services/json_repair.dart';

void main() {
  group('JsonRepair.simplify', () {
    test('drops trailing commas outside strings', () {
      expect(JsonRepair.simplify('{"a":1,}'), '{"a":1}');
      expect(JsonRepair.simplify('{"a":[1,2,]}'), '{"a":[1,2]}');
    });

    test('never touches commas inside strings (CSS/JS payloads)', () {
      const input = '{"css":"grid-template-columns: 1fr, 1fr;",}';
      expect(JsonRepair.simplify(input),
          '{"css":"grid-template-columns: 1fr, 1fr;"}');
    });

    test('turns smart quotes around values into straight quotes', () {
      expect(JsonRepair.simplify('{\u201Centry\u201D:\u201Cindex.html\u201D}'),
          '{"entry":"index.html"}');
    });

    test('keeps escaped quotes and backslashes', () {
      expect(JsonRepair.simplify(r'{"js":"const s = \"a\";"}'),
          r'{"js":"const s = \"a\";"}');
    });

    test('escapes raw line breaks and tabs inside strings', () {
      // Real control characters, as a model emits them inside a JSON string.
      const raw = '{"index.html":"<!doctype html>\n<html>\n\tx\r\n</html>"}';
      final decoded =
          jsonDecode(JsonRepair.simplify(raw)) as Map<String, dynamic>;
      expect(decoded['index.html'], '<!doctype html>\n<html>\n\tx\r\n</html>');
    });

    test('a backslash before a raw line break becomes a line-break escape', () {
      const raw = '{"a":"one\\\ntwo"}';
      final decoded =
          jsonDecode(JsonRepair.simplify(raw)) as Map<String, dynamic>;
      expect(decoded['a'], 'one\ntwo');
    });

    test('valid pretty-printed JSON with escapes is left unchanged', () {
      const valid = '{\n  "a": "x\\ny",\n  "b": "q\\"z"\n}';
      expect(JsonRepair.simplify(valid), valid);
    });
  });
}
