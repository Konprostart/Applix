import 'package:applix/services/script_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

/// The "Notes" app as the model tends to write it: helpers marked with
/// `export`, a classic script tag and the kit loaded with a plain src.
const _notesHtml = '''<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no,viewport-fit=cover">
<style>body{font-family:system-ui,Roboto,sans-serif}</style>
</head>
<body>
<div class="ax-appbar"><div class="ax-appbar__title">Notes</div></div>
<div class="ax-page">
  <input class="ax-input" id="title">
  <button class="ax-btn" onclick="addNote()">Add</button>
  <ul id="list" class="ax-list"></ul>
</div>
<script src="applix-ui.js"></script>
<script>
var notes = [];
export function addNote() {
  var t = document.getElementById('title').value;
  if (!t) { toast('Enter a title'); return; }
  notes.push(t);
  render();
}
export const STORAGE_KEY = "notes";
export default function render() {
  document.getElementById('list').innerHTML = notes.map(function (n) { return '<li>' + n + '</li>'; }).join('');
}
export { notes };
</script>
</body>
</html>''';

/// Classic script bodies only: anything in a plain `<script>` (no type module).
Iterable<String> _classicBodies(String html) sync* {
  final tag = RegExp(r'<script\b([^>]*)>([\s\S]*?)</script>', caseSensitive: false);
  for (final m in tag.allMatches(html)) {
    final attrs = m.group(1) ?? '';
    if (RegExp(r'type\s*=\s*["\x27]?module', caseSensitive: false).hasMatch(attrs)) continue;
    yield m.group(2) ?? '';
  }
}

final _exportWord = RegExp(r'(^|[^\w$])export\b');

void main() {
  group('Notes app', () {
    test('no export word survives in any classic script after normalizing', () {
      final result = ScriptSanitizer.normalize(_notesHtml, const {});
      for (final body in _classicBodies(result.html)) {
        expect(_exportWord.hasMatch(body), isFalse, reason: body);
      }
    });

    test('the functions stay global and the handlers still exist', () {
      final result = ScriptSanitizer.normalize(_notesHtml, const {});
      final bodies = _classicBodies(result.html).join('\n');
      expect(bodies, contains('function addNote()'));
      expect(bodies, contains('function render()'));
      expect(bodies, contains('var notes = [];'));
      expect(bodies, contains('const STORAGE_KEY = "notes";'));
      expect(bodies, isNot(contains('export {')));
    });

    test('the kit stays a classic tag and its helpers become globals', () {
      final result = ScriptSanitizer.normalize(_notesHtml, const {
        'applix-ui.js': 'export function toast(m) { return m; }',
      });
      expect(result.html, contains('<script src="applix-ui.js"></script>'));
      expect(result.html, isNot(contains('type="module" src="applix-ui.js"')));
      expect(result.files['applix-ui.js'], contains('function toast(m)'));
      expect(result.files['applix-ui.js'], isNot(contains('export')));
    });

    test('a project file with export is cleaned when loaded as a classic src', () {
      const html = '<html><body><script src="app.js"></script></body></html>';
      final result = ScriptSanitizer.normalize(html, const {
        'app.js': 'export function render() {}\nrender();',
      });
      expect(result.files['app.js'], isNot(contains('export')));
      expect(result.files['app.js'], contains('function render() {}'));
    });

    test('a top-level function used by an inline handler is bound to window', () {
      const html = '<html><body><button onclick="openAddForm()">+</button>'
          '<script>\nfunction openAddForm() { return 1; }\n</script></body></html>';
      final out = ScriptSanitizer.normalize(html, const {}).html;
      expect(out, contains('try{window.openAddForm = openAddForm;}catch(e){}'));
      expect(out.indexOf('applix-handler-bind'), greaterThan(out.indexOf('function openAddForm')));
    });

    test('a visibility guard is added to the head once and never hides display', () {
      const html = '<html><head><title>x</title></head><body><div id="app">Hi</div></body></html>';
      final once = ScriptSanitizer.normalize(html, const {}).html;
      expect(once, contains('<style id="applix-visibility-guard">'));
      expect(once.indexOf('applix-visibility-guard'), lessThan(once.indexOf('<title>')));
      expect(once, isNot(contains('display:none')));
      final twice = ScriptSanitizer.normalize(once, const {}).html;
      expect(twice, once);
    });

    test('an empty body gets a visible card instead of a black screen', () {
      const html = '<html><head></head><body></body></html>';
      final out = ScriptSanitizer.normalize(html, const {}).html;
      expect(out, contains('id="applix-visible-fallback"'));
      expect(out, contains('This screen came back empty'));
      final twice = ScriptSanitizer.normalize(out, const {}).html;
      expect(twice, out);
    });

    test('a body with a heading and a button is left without a fallback', () {
      const html = '<html><head></head><body><h1>Notes</h1>'
          '<button onclick="go()">Add</button></body></html>';
      final out = ScriptSanitizer.normalize(html, const {}).html;
      expect(out, isNot(contains('applix-visible-fallback')));
    });

    test('a root container hidden with display none is made visible', () {
      const html = '<html><head><style>#app { display: none; color: #fff; }</style>'
          '</head><body><div id="app">Hi</div></body></html>';
      final out = ScriptSanitizer.normalize(html, const {}).html;
      expect(out, contains('#app { display: block; color: #fff; }'));
      expect(out, isNot(contains('display: none')));
    });

    test('a display none on an ordinary class is not touched', () {
      const html = '<html><head><style>.modal { display: none; }</style>'
          '</head><body><div class="modal">x</div></body></html>';
      final out = ScriptSanitizer.normalize(html, const {}).html;
      expect(out, contains('.modal { display: none; }'));
    });

    test('binding is added once even when normalized twice', () {
      const html = '<html><body><button onclick="save()">x</button></body></html>';
      final once = ScriptSanitizer.normalize(html, const {}).html;
      final twice = ScriptSanitizer.normalize(once, const {}).html;
      expect(twice, once);
    });

    test('export inside a string literal is left alone', () {
      const code = "var s = 'export function x() {}';\nexport function y() {}";
      final out = ScriptSanitizer.stripExports(code);
      expect(out, contains("'export function x() {}'"));
      expect(out, contains('function y() {}'));
    });
  });
}
