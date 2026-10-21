import 'package:flutter_test/flutter_test.dart';
import 'package:applix/services/app_patch.dart';
import 'package:applix/services/app_project.dart';

const _html = '''<!doctype html>
<html><body><button id="a">Old</button><p>Keep me</p></body></html>''';

String _response(String edits, {String files = ''}) =>
    '{"applix_patch":1,"edits":[$edits]${files.isEmpty ? '' : ',"files":{$files}'}}';

void main() {
  group('AppPatch', () {
    test('replaces only the requested code', () {
      final current = AppProject.singleFile(_html);
      final outcome = AppPatch.applyToProject(
        _response('{"op":"replace","find":"Old","replace":"New"}'),
        current,
      );
      expect(outcome, isNotNull);
      expect(outcome!.ok, isTrue);
      expect(outcome.project!.entryHtml, contains('>New<'));
      expect(outcome.project!.entryHtml, contains('Keep me'));
      expect(outcome.project!.entryHtml.contains('Old'), isFalse);
    });

    test('inserts after an anchor and deletes code', () {
      final outcome = AppPatch.applyToProject(
        _response('{"op":"insert_after","find":"</p>","content":"<span>Added</span>"},'
            '{"op":"delete","find":"Old"}'),
        AppProject.singleFile(_html),
      );
      expect(outcome!.ok, isTrue);
      expect(outcome.project!.entryHtml, contains('<p>Keep me</p><span>Added</span>'));
      expect(outcome.project!.entryHtml, contains('<button id="a"></button>'));
    });

    test('rejects a find string that is not unique', () {
      final current = AppProject.singleFile('<html><body><p>x</p><p>x</p></body></html>');
      final outcome = AppPatch.applyToProject(
        _response('{"op":"replace","find":"x","replace":"y"}'),
        current,
      );
      expect(outcome!.ok, isFalse);
      expect(outcome.error, contains('not unique'));
    });

    test('rejects a find string that is missing', () {
      final outcome = AppPatch.applyToProject(
        _response('{"op":"replace","find":"Missing","replace":"y"}'),
        AppProject.singleFile(_html),
      );
      expect(outcome!.ok, isFalse);
      expect(outcome.error, contains('not found'));
    });

    test('returns null for a normal full-app answer', () {
      expect(AppPatch.applyToProject(_html, AppProject.singleFile(_html)), isNull);
      expect(
        AppPatch.applyToProject(
          '{"applix":2,"entry":"index.html","files":{"index.html":"<html></html>"}}',
          AppProject.singleFile(_html),
        ),
        isNull,
      );
    });

    test('supports whole-file replacements without losing other files', () {
      final current = AppProject(files: {
        'index.html': _html,
        'src/app.js': 'old();',
      });
      final outcome = AppPatch.applyToProject(
        _response('', files: '"src/app.js":"new();"'),
        current,
      );
      expect(outcome!.ok, isTrue);
      expect(outcome.project!.files['src/app.js'], 'new();');
      expect(outcome.project!.files['index.html'], _html);
    });

    test('rejects an unsafe file path', () {
      final outcome = AppPatch.applyToProject(
        _response('', files: '"../evil.js":"x"'),
        AppProject.singleFile(_html),
      );
      expect(outcome!.ok, isFalse);
    });

    test('rejects an unsupported patch version', () {
      final outcome = AppPatch.applyToProject(
        '{"applix_patch":2,"edits":[{"op":"replace","find":"Old","replace":"New"}]}',
        AppProject.singleFile(_html),
      );
      expect(outcome!.ok, isFalse);
      expect(outcome.error, contains('version'));
    });

    test('applies a patch to plain HTML', () {
      final outcome = AppPatch.applyToHtml(
        _response('{"op":"replace","find":"Old","replace":"New"}'),
        _html,
      );
      expect(outcome!.ok, isTrue);
      expect(outcome.project!.entryHtml, contains('New'));
    });

    test('fails when a file patch is used on plain HTML', () {
      final outcome = AppPatch.applyToHtml(
        _response('', files: '"style.css":"body{}"'),
        _html,
      );
      expect(outcome!.ok, isFalse);
    });
  });
}
