import 'package:applix/services/script_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScriptSanitizer.stripExports', () {
    test('keeps exported declarations as plain globals', () {
      const code = 'export function addNote(t) { return t; }\n'
          'export const KEY = "notes";\n'
          'export async function load() {}\n';
      final out = ScriptSanitizer.stripExports(code);
      expect(out, contains('function addNote(t)'));
      expect(out, contains('const KEY = "notes";'));
      expect(out, contains('async function load()'));
      expect(out, isNot(contains('export')));
    });

    test('removes export lists', () {
      const code = 'function a() {}\nfunction b() {}\nexport { a, b };\n';
      final out = ScriptSanitizer.stripExports(code);
      expect(out, contains('function a() {}'));
      expect(out, isNot(contains('export')));
    });

    test('turns export default function into a plain function', () {
      final out = ScriptSanitizer.stripExports('export default function main() {}');
      expect(out.trim(), 'function main() {}');
    });

    test('turns an export default expression into a variable', () {
      final out = ScriptSanitizer.stripExports('export default { title: "Notes" };');
      expect(out, contains('var defaultExport = { title: "Notes" };'));
    });

    test('leaves code without exports untouched', () {
      const code = 'const x = 1;\nconsole.log(x);';
      expect(ScriptSanitizer.stripExports(code), code);
    });
  });

  group('ScriptSanitizer.normalize', () {
    test('cleans a classic inline script that uses export', () {
      const html = '<html><body><script>\nexport function save() {}\n'
          'save();\n</script></body></html>';
      final out = ScriptSanitizer.normalize(html, const {}).html;
      expect(out, isNot(contains('export function')));
      expect(out, contains('function save() {}'));
    });

    test('switches an inline script with import to a module', () {
      const html = '<html><body><script>\nimport { toast } from "./applix-ui.js";\n'
          'toast("hi");\n</script></body></html>';
      final out = ScriptSanitizer.normalize(html, const {}).html;
      expect(out, contains('<script type="module">'));
    });

    test('strips exports from a classic src file and keeps its code', () {
      const html = '<html><body><script src="app.js"></script></body></html>';
      final result = ScriptSanitizer.normalize(html, const {
        'app.js': 'export function render() { return 1; }\nrender();',
      });
      expect(result.html, contains('<script src="app.js">'));
      expect(result.files['app.js'], contains('function render()'));
      expect(result.files['app.js'], isNot(contains('export')));
    });

    test('makes a src file with imports a module', () {
      const html = '<html><body><script src="src/app.js"></script></body></html>';
      final result = ScriptSanitizer.normalize(html, const {
        'src/app.js': "import { toast } from './applix-ui.js';\ntoast('x');",
      });
      expect(result.html, contains('<script type="module" src="src/app.js">'));
      expect(result.files['src/app.js'], contains('import { toast }'));
    });

    test('never touches an explicit module script', () {
      const html = '<html><body><script type="module" src="app.js"></script></body></html>';
      final result = ScriptSanitizer.normalize(html, const {
        'app.js': 'export const a = 1;',
      });
      expect(result.html, contains('<script type="module" src="app.js"></script>'));
      expect(result.files['app.js'], 'export const a = 1;');
    });

    test('a calendar with an export is still wired up after normalizing', () {
      const html = '<!DOCTYPE html><html><head></head><body>'
          '<div id="grid"></div><button onclick="next()">Next</button>'
          '<script>\nexport let month = 0;\nfunction next() { month++; }\n</script>'
          '</body></html>';
      final out = ScriptSanitizer.normalize(html, const {}).html;
      expect(out, isNot(contains('export let')));
      expect(out, contains('let month = 0;'));
      expect(out, contains('function next()'));
    });
  });
}
