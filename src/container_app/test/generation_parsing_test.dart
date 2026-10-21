import 'package:flutter_test/flutter_test.dart';
import 'package:applix/services/ai_response.dart';
import 'package:applix/services/app_project.dart';

void main() {
  group('AI response parsing', () {
    test('extracts the document from prose, BOM and a trailing summary', () {
      final response = '\uFEFFHere is the app:\n\n```html\n'
          '<!DOCTYPE html><html><body><h1>Hi</h1></body></html>\n```\n\n'
          'Summary of changes: fixed the layout.';
      final html = AiResponse.extractAppHtml(response);
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, endsWith('</html>'));
      expect(html, isNot(contains('Summary')));
      expect(html, isNot(contains('```')));
    });

    test('picks the HTML fence, not a prose fence', () {
      final response = 'Notes:\n```text\nhello\n```\n'
          '```html\n<!doctype html><html><body>ok</body></html>\n```';
      expect(AiResponse.extractAppHtml(response), contains('<body>ok</body>'));
    });

    test('returns empty when there is no app', () {
      expect(AiResponse.extractAppHtml('I cannot do that.'), isEmpty);
      expect(AiResponse.extractAppHtml('```json\n{"a":1}\n```'), isEmpty);
    });

    test('parses a fenced project with trailing commas and smart quotes', () {
      final response = 'Here is the project:\n```json\n'
          '{"applix":2,“entry”:”index.html”,"files":{'
          '"index.html":"<!doctype html><html><body>ok</body></html>",'
          '"src/app.js":"console.log(1);",}}\n```';
      final project = AppProject.parseModelOutput(response);
      expect(project.isMultiFile, isTrue);
      expect(project.entryHtml, contains('<body>ok</body>'));
      expect(project.files['src/app.js'], 'console.log(1);');
    });

    test('parses bare JSON surrounded by prose', () {
      final response = 'Sure. {"applix":2,"entry":"index.html","files":'
          '{"index.html":"<!doctype html><html><body>bare</body></html>"}} Done.';
      final project = AppProject.parseModelOutput(response);
      expect(project.entryHtml, contains('bare'));
    });

    test('falls back to HTML when the JSON has no files', () {
      final response = '{"note":"no files"}\n'
          '<!doctype html><html><body>fallback</body></html>';
      final project = AppProject.parseModelOutput(response);
      expect(project.entryHtml, contains('fallback'));
    });

    test('rejects a response with neither JSON nor HTML', () {
      final project = AppProject.parseModelOutput('Sorry, I cannot help.');
      expect(project.entryHtml, isEmpty);
    });
  });
}
