import 'dart:convert';
import 'dart:io';

import 'package:applix/services/bridge_linter.dart';
import 'package:flutter_test/flutter_test.dart';

const _index = BridgeIndex(
  {
    'audio': {'play', 'pause'},
    'storage': {'saveFile'},
    'camera': {'sharePhoto'},
  },
  {'save', 'load'},
);

BridgeLinter get _linter => const BridgeLinter(_index);

String _page(String script) => '<!DOCTYPE html>\n<html>\n<script>\n$script\n</script>\n</html>';

void main() {
  group('direct calls', () {
    test('valid calls produce no issues', () {
      final issues = _linter.lint(_page(
        "iappyx.audio.play('a.mp3'); iappyx.save('k','v'); window.iappyx.camera.sharePhoto('x');",
      ));
      expect(issues, isEmpty);
    });

    test('unknown method is reported with its line', () {
      final issues = _linter.lint(_page("var s = 'x';\niappyx.audio.playSound(s);"));
      expect(issues, hasLength(1));
      expect(issues.first.kind, BridgeIssueKind.unknownMethod);
      expect(issues.first.call, 'iappyx.audio.playSound');
      expect(issues.first.line, 5);
      expect(issues.first.snippet, contains('playSound'));
    });

    test('unknown module is reported', () {
      final issues = _linter.lint(_page('iappyx.torch.on();'));
      expect(issues, hasLength(1));
      expect(issues.first.kind, BridgeIssueKind.unknownModule);
      expect(issues.first.call, 'iappyx.torch.on');
      expect(issues.first.line, 4);
    });

    test('unknown top-level method is reported', () {
      final issues = _linter.lint(_page('iappyx.makeCoffee();'));
      expect(issues, hasLength(1));
      expect(issues.first.kind, BridgeIssueKind.unknownTopLevel);
      expect(issues.first.call, 'iappyx.makeCoffee');
    });

    test('duplicates are collapsed to the first occurrence', () {
      final issues = _linter.lint(_page(
        'iappyx.audio.nope();\niappyx.audio.nope();',
      ));
      expect(issues, hasLength(1));
      expect(issues.first.line, 4);
    });
  });

  group('false-positive guards', () {
    test('comments and strings are ignored', () {
      final issues = _linter.lint(_page(
        "// iappyx.fake.run()\n"
        '/* iappyx.other.fail() */\n'
        'var a = "iappyx.string.call()";\n'
        "var b = 'iappyx.single.call()';\n"
        'var c = `iappyx.template.call()`;',
      ));
      expect(issues, isEmpty);
    });

    test('dynamic access is skipped', () {
      final issues = _linter.lint(_page(
        "iappyx['fake']['run']();\nvar m = 'audio'; iappyx[m].fallback();",
      ));
      expect(issues, isEmpty);
    });

    test('bare module objects are allowed', () {
      final issues = _linter.lint(_page(
        'var a = iappyx.audio;\nvar b = iappyx.save;\nvar c = window.iappyx.storage;',
      ));
      expect(issues, isEmpty);
    });

    test('scripts outside <script> are ignored', () {
      final issues = _linter.lint(
        '<!DOCTYPE html>\n<p>iappyx.fake.run()</p>\n<script>iappyx.save("a","b");</script>',
      );
      expect(issues, isEmpty);
    });
  });

  group('repair message', () {
    test('lists call, line and instruction', () {
      final issues = _linter.lint(_page('iappyx.audio.playSound("x");'));
      final message = BridgeLinter.buildRepairMessage(issues);
      expect(message, contains('iappyx.audio.playSound'));
      expect(message, contains('line 4'));
      expect(message, contains('Return the complete corrected HTML file only'));
    });
  });

  group('real index', () {
    test('demos contain no unknown bridge calls', () {
      final indexJson =
          jsonDecode(File('assets/bridge_index.json').readAsStringSync())
              as Map<String, dynamic>;
      final linter = BridgeLinter(BridgeIndex.fromJson(indexJson));
      final demoDir = Directory('../../demos');
      expect(demoDir.existsSync(), isTrue,
          reason: 'run flutter test from src/container_app');

      final files = demoDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.html'))
          .toList();
      expect(files, isNotEmpty);

      final failures = <String>[];
      for (final file in files) {
        final issues = linter.lint(file.readAsStringSync());
        if (issues.isNotEmpty) {
          failures.add('${file.path}: ${issues.map((i) => i.consoleLine).join('; ')}');
        }
      }
      expect(failures, isEmpty);
    });
  });
}
