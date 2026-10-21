import 'package:applix/services/dev_text_sanitizer.dart';
import 'package:applix/services/ui_auditor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DevTextSanitizer', () {
    test('removes a changes and improvements section with its content', () {
      const html = '''
<html><head><title>Radio</title></head><body>
  <h1>Radio</h1>
  <p>The best radio app.</p>
  <h2>Changes and Improvements</h2>
  <ul><li>New player</li><li>Faster sync</li></ul>
  <h2>Settings</h2>
  <p>Pick a station.</p>
</body></html>''';
      final clean = removeDevText(html);
      expect(clean.contains('Changes and Improvements'), isFalse);
      expect(clean.contains('New player'), isFalse);
      expect(clean.contains('Faster sync'), isFalse);
      // the real content stays
      expect(clean.contains('The best radio app.'), isTrue);
      expect(clean.contains('Pick a station.'), isTrue);
      expect(clean.contains('<h2>Settings</h2>'), isTrue);
    });

    test('removes a changelog heading with everything until the next heading', () {
      const html = '''
<body>
  <h1>My App</h1>
  <h2>Changelog</h2>
  <p>Version 1.0.0</p>
  <p>Fixed a bug.</p>
  <h1>About</h1>
  <p>Made with care.</p>
</body>''';
      final clean = removeDevText(html);
      expect(clean.contains('Changelog'), isFalse);
      expect(clean.contains('Version 1.0.0'), isFalse);
      expect(clean.contains('Fixed a bug.'), isFalse);
      expect(clean.contains('About'), isTrue);
      expect(clean.contains('Made with care.'), isTrue);
    });

    test('removes what is new and version history', () {
      for (final heading in [
        "What's New",
        'Version History',
        'New in this version',
      ]) {
        final html =
            '<body><h1>App</h1><h2>$heading</h2><p>secret</p><h2>Help</h2><p>ok</p></body>';
        final clean = removeDevText(html);
        expect(clean.contains('secret'), isFalse, reason: heading);
        expect(clean.contains('Help'), isTrue, reason: heading);
      }
    });

    test('removes a developer text that has no heading', () {
      const html = '<body><p>Changelog</p><p>Real content</p></body>';
      final clean = removeDevText(html);
      expect(clean.contains('Changelog'), isFalse);
      expect(clean.contains('Real content'), isTrue);
    });

    test('keeps app content that only mentions the words', () {
      const html = '''
<body>
  <h1>Release notes</h1>
  <p>This app shows the release notes of your favourite show.</p>
  <h2>Tracks</h2><p>Three tracks today.</p>
</body>''';
      final clean = removeDevText(html);
      expect(clean.contains('This app shows the release notes'), isTrue);
      expect(clean.contains('Three tracks today.'), isTrue);
    });

    test('leaves a clean app untouched', () {
      const html = '<html><head></head><body><h1>Todo</h1><ul><li>Milk</li></ul></body></html>';
      expect(removeDevText(html), html);
    });
  });

  group('UiAuditor developer text rule', () {
    test('flags a changes and improvements section', () {
      const html = '<body><h1>App</h1><h2>Changes and Improvements</h2><p>x</p></body>';
      final codes = UiAuditor.audit(html).map((v) => v.code).toList();
      expect(codes, contains('developer-text'));
    });

    test('does not flag a normal app', () {
      const html = '<body><h1>App</h1><p>Hello</p></body>';
      final codes = UiAuditor.audit(html).map((v) => v.code).toList();
      expect(codes, isNot(contains('developer-text')));
    });
  });
}
