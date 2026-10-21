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
  });
}
