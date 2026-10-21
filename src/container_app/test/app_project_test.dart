import 'dart:convert';

import 'package:applix/services/app_project.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppProject.parseModelOutput', () {
    test('parses a fenced project JSON block', () {
      final response = '```json\n${jsonEncode({
        'applix': 2,
        'entry': 'index.html',
        'name': 'Ticker',
        'routes': ['/', '/settings'],
        'files': {
          'index.html': '<!doctype html><html><body><div id="app"></div>'
              '<script type="module" src="src/app.js"></script></body></html>',
          'src/app.js': "import { tick } from './ticker.js'; tick();",
          'src/ticker.js': 'export function tick(){}',
          'style.css': 'body{margin:0}',
        },
      })}\n```';
      final project = AppProject.parseModelOutput(response);
      expect(project.entry, 'index.html');
      expect(project.name, 'Ticker');
      expect(project.routes, ['/', '/settings']);
      expect(project.files.length, 4);
      expect(project.entryHtml, contains('<div id="app">'));
      expect(project.isMultiFile, isTrue);
      expect(project.validate(), isNull);
    });

    test('parses a bare project JSON block', () {
      final response = '{"applix":2,"entry":"index.html",'
          '"files":{"index.html":"<p>x</p>","app.js":"1"}}';
      final project = AppProject.parseModelOutput(response);
      expect(project.entryHtml, '<p>x</p>');
      expect(project.files['app.js'], '1');
    });

    test('falls back to a single HTML document with trailing prose', () {
      final response = '<!DOCTYPE html>\n<html><body>Hi</body></html>\n'
          'Summary of changes made: added a button.';
      final project = AppProject.parseModelOutput(response);
      expect(project.isMultiFile, isFalse);
      expect(project.entry, 'index.html');
      expect(project.entryHtml, contains('<body>Hi</body>'));
      expect(project.entryHtml, isNot(contains('Summary')));
    });

    test('recovers a multi-file project with raw line breaks in its strings',
        () {
      // Models often emit literal newlines inside JSON strings. That is
      // invalid JSON, but the project is still usable after repair.
      const response = '```json\n'
          '{"applix":2,"entry":"index.html","files":{'
          '"index.html":"<!doctype html>\n<html><body>'
          '<script src=\\"src/app.js\\"></script></body></html>",'
          '"src/app.js":"console.log(1);\n"}}'
          '\n```';
      final project = AppProject.parseModelOutput(response);
      expect(project.isMultiFile, isTrue);
      expect(project.entry, 'index.html');
      expect(project.files['src/app.js'], 'console.log(1);\n');
      expect(project.entryHtml, contains('<html><body>'));
      expect(project.entryHtml, contains('src="src/app.js"'));
      expect(project.validate(), isNull);
    });

    test('a JSON object without files is ignored', () {
      final project = AppProject.parseModelOutput('{"a":1}');
      expect(project.files, isEmpty);
    });

    test('empty or prose-only answers yield an empty project', () {
      expect(AppProject.parseModelOutput('').files, isEmpty);
      expect(AppProject.parseModelOutput('No app for this request.').files,
          isEmpty);
    });

    test('unsafe paths are dropped, the safe ones are kept', () {
      final response = jsonEncode({
        'entry': 'index.html',
        'files': {
          'index.html': '<p>ok</p>',
          '../secret.js': 'bad',
          '/etc/passwd': 'bad',
          'src/a b.js': 'bad spaces',
          'src/ok.js': 'good',
        },
      });
      final project = AppProject.parseModelOutput(response);
      expect(project.files.keys, containsAll(['index.html', 'src/ok.js']));
      expect(project.files.keys, isNot(contains('../secret.js')));
      expect(project.files.keys, isNot(contains('/etc/passwd')));
      expect(project.files.keys, isNot(contains('src/a b.js')));
    });

    test('a root entry with another name becomes index.html', () {
      final project = AppProject.parseModelOutput(jsonEncode({
        'entry': 'main.html',
        'files': {'main.html': '<p>main</p>'},
      }));
      expect(project.entry, 'index.html');
      expect(project.entryHtml, '<p>main</p>');
      expect(project.validate(), isNull);
    });

    test('a nested entry is rejected by validate', () {
      final project = AppProject.parseModelOutput(jsonEncode({
        'entry': 'pages/index.html',
        'files': {'pages/index.html': '<p>x</p>', 'app.js': '1'},
      }));
      expect(project.validate(), isNotNull);
    });

    test('missing entry falls back to the only HTML file', () {
      final project = AppProject.parseModelOutput(jsonEncode({
        'entry': 'nope.html',
        'files': {'index.html': '<p>x</p>', 'app.js': '1'},
      }));
      expect(project.entry, 'index.html');
      expect(project.validate(), isNull);
    });
  });

  group('AppProject packaging', () {
    AppProject sample() => AppProject(
          entry: 'index.html',
          name: 'Demo',
          routes: const ['/'],
          files: const {
            'index.html': '<html><body>ok</body></html>',
            'src/app.js': 'console.log(1)',
          },
        );

    test('manifest carries format, entry and routes', () {
      final manifest = jsonDecode(sample().manifestJson()) as Map;
      expect(manifest['applix'], AppProject.format);
      expect(manifest['entry'], 'index.html');
      expect(manifest['routes'], ['/']);
    });

    test('injection files include app.json and every module', () {
      final files = sample().injectionFiles();
      expect(files.keys, containsAll(['index.html', 'src/app.js', 'app.json']));
      expect(files['app.json'], contains('"entry": "index.html"'));
    });

    test('extra files exclude the entry but include the manifest', () {
      final extra = sample().extraFiles();
      expect(extra.containsKey('index.html'), isFalse);
      expect(extra.keys, containsAll(['src/app.js', 'app.json']));
    });

    test('dev text after </html> is stripped from every HTML file', () {
      final project = AppProject(files: {
        'index.html': '<html><body>x</body></html>\nSummary of changes made: 1. y',
        'other.html': '<html></html>\nSummary of changes made: 2. z',
        'app.js': '// Summary of changes made\n1;',
      });
      final files = project.injectionFiles();
      expect(files['index.html'], isNot(contains('Summary')));
      expect(files['other.html'], isNot(contains('Summary')));
      expect(files['app.js'], contains('Summary of changes made'));
    });

    test('validate rejects a missing entry, bad type and oversized file', () {
      expect(const AppProject(files: {}).validate(), isNotNull);
      expect(
        const AppProject(files: {'index.html': '<p>'}).validate(),
        isNull,
      );
      expect(
        const AppProject(files: {'index.html': '<p>', 'logo.png': 'x'})
            .validate(),
        isNotNull,
      );
      expect(
        AppProject(files: {'index.html': '<p>', 'big.js': 'x' * (1024 * 1024 + 1)})
            .validate(),
        isNotNull,
      );
    });
  });
}
