import 'package:flutter_test/flutter_test.dart';
import 'package:applix/services/preview_origin.dart';

void main() {
  group('PreviewOrigin', () {
    test('is a stable https origin per app', () {
      final url = PreviewOrigin.baseUrl('<html></html>', {'a.js': 'x'});
      expect(url, startsWith('https://app-'));
      expect(url, endsWith('.localhost/'));
      expect(PreviewOrigin.baseUrl('<html></html>', {'a.js': 'x'}), url);
    });

    test('different apps get different origins', () {
      final first = PreviewOrigin.baseUrl('<html>A</html>', {});
      final second = PreviewOrigin.baseUrl('<html>B</html>', {});
      expect(first, isNot(second));
    });

    test('project files take part in the origin', () {
      final first = PreviewOrigin.baseUrl('<html></html>', {'a.js': 'x'});
      final second = PreviewOrigin.baseUrl('<html></html>', {'a.js': 'y'});
      expect(first, isNot(second));
    });

    test('file order does not change the origin', () {
      final first = PreviewOrigin.baseUrl(
          '<html></html>', {'a.js': 'x', 'b.css': 'y'});
      final second = PreviewOrigin.baseUrl(
          '<html></html>', {'b.css': 'y', 'a.js': 'x'});
      expect(first, second);
    });
  });
}
