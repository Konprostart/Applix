import 'package:flutter_test/flutter_test.dart';
import '../lib/services/ai_response.dart';

void main() {
  group('AiResponse.extractAppHtml', () {
    test('returns the fenced document and drops prose before and after', () {
      final response = 'Here is your app:\n'
          '```html\n'
          '<html><body><h1>Radio</h1></body></html>\n'
          '```\n'
          'Summary of changes made:** 1. Added a new station grid. '
          '2. Updated the font-family in the CSS. '
          '3. Changed the <input> element to use the .ax-input class.';
      final html = AiResponse.extractAppHtml(response);
      expect(html, '<html><body><h1>Radio</h1></body></html>');
    });

    test('drops a summary the model appended after </html> without a fence',
        () {
      final response = '<html><body><p>Coin list</p></body></html>\n'
          'Summary of changes made:** 1. Added a cart. 2. Changed the '
          '<input> element to use the .ax-input class.';
      final html = AiResponse.extractAppHtml(response);
      expect(html, '<html><body><p>Coin list</p></body></html>');
    });

    test('does not cut at a <input mentioned in the leading prose', () {
      final response = 'I changed the <input> element and now here it is:\n'
          '<!DOCTYPE html>\n<html><body><p>Real app</p></body></html>';
      final html = AiResponse.extractAppHtml(response);
      expect(html,
          '<!DOCTYPE html>\n<html><body><p>Real app</p></body></html>');
    });

    test('takes the fenced html even when an earlier block contains prose',
        () {
      final response = 'Notes:\n```\nsome reminder text with <tags>\n```\n'
          '```html\n<html><body><p>App</p></body></html>\n```';
      final html = AiResponse.extractAppHtml(response);
      expect(html, '<html><body><p>App</p></body></html>');
    });

    test('returns an empty string when there is no document', () {
      final response = "I couldn't build that, sorry.";
      expect(AiResponse.extractAppHtml(response), '');
    });

    test('keeps a partly truncated document so the repair pass can retry it',
        () {
      final html = AiResponse.extractAppHtml(
          '<!DOCTYPE html>\n<html><body><p>Cut off mid...</');
      expect(html.startsWith('<html'), isFalse, reason: 'doctype survives');
      expect(html.startsWith('<!DOCTYPE'), isTrue);
    });
  });
}
