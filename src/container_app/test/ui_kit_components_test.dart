import 'dart:convert';
import 'dart:io';

import 'package:applix/services/app_project.dart';
import 'package:applix/services/ui_kit.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('UI kit assets', () {
    late String css;
    late String js;

    setUpAll(() {
      css = _read('assets/applix-ui.css');
      js = _read('assets/applix-ui.js');
    });

    test('the stylesheet defines the shared components', () {
      for (final selector in [
        '.ax-tabs',
        '.ax-tab--active',
        '.ax-bottom-nav',
        '.ax-bottom-nav__item--active',
        '.ax-segmented',
        '.ax-segmented__item--active',
        '.ax-table',
        '.ax-num',
        '.ax-sheet__title',
        '.ax-sheet__body',
        '.ax-sheet__actions',
        '.ax-toast__action',
        '.ax-anim-in',
        '.ax-press',
        '.ax-icon',
        '.ax-icon-btn',
        '.ax-select',
        '.ax-check',
        '.ax-radio',
        '.ax-search',
        '.ax-stepper',
        '.ax-chart__bars',
        '.ax-bar',
        '.ax-sparkline',
        '.ax-donut',
        '.ax-stat-row',
      ]) {
        expect(css, contains(selector), reason: 'missing $selector');
      }
      expect(css, contains('prefers-reduced-motion'));
      expect(css, contains('tabular-nums'));
      expect(css, contains('--ax-safe-bottom'));
    });

    test('the module exports the documented helpers and is self-contained', () {
      expect(js, contains('export const UI_KIT_VERSION = 2;'));
      for (final fn in [
        'toast',
        'openSheet',
        'confirmDialog',
        'mountTabs',
        'mountBottomNav',
        'mountSegmented',
        'stagger',
        'icon',
        'mountIcons',
        'sparkline',
        'barChart',
        'donut',
      ]) {
        expect(js, contains('export function $fn('), reason: 'missing $fn');
      }
      expect(js, contains('export default {'));
      expect(js, isNot(matches(RegExp(r'^\s*import\s', multiLine: true))));
      expect(js, isNot(contains('require(')));
      expect(js, isNot(contains('iappyx')));
    });

    test('every .ax- class taught by the prompt exists in the stylesheet', () {
      final prompt = _read('assets/system_prompt.md');
      final taught = RegExp(r'\.ax-[A-Za-z0-9_-]+')
          .allMatches(prompt)
          .map((m) => m.group(0)!)
          .toSet();
      expect(taught, isNotEmpty);
      for (final cls in taught) {
        expect(css, contains(cls), reason: '$cls is documented but missing');
      }
    });

    test('the prompt requires the kit instead of hand-written widgets', () {
      final prompt = _read('assets/system_prompt.md');
      expect(prompt, contains('applix-ui.js'));
      expect(prompt, contains("from './applix-ui.js'"));
      expect(prompt, contains('mountBottomNav'));
      expect(prompt, contains('confirmDialog'));
      expect(prompt, contains('Never build bottom navigation'));
      expect(prompt, contains('sparkline'));
      expect(prompt, contains('barChart'));
      expect(prompt, contains('mountIcons'));
    });
  });

  group('UI kit packaging contract', () {
    test('the Dart kit names match the manifest contract', () {
      expect(UiKit.cssFileName, AppProject.uiKitCss);
      expect(UiKit.jsFileName, AppProject.uiKitJs);
      expect(UiKit.version, AppProject.uiKitVersion);
    });

    test('app.json advertises the kit so multi-file apps can import it', () {
      final manifest = jsonDecode(
        AppProject.singleFile('<html><body>x</body></html>').manifestJson(),
      ) as Map<String, dynamic>;
      final kit = manifest['uiKit'] as Map<String, dynamic>;
      expect(kit['version'], 2);
      expect(kit['css'], 'applix-ui.css');
      expect(kit['js'], 'applix-ui.js');
    });

    test('a built project carries the manifest with the kit entry', () {
      const project = AppProject(files: {
        'index.html': '<html><body>x</body></html>',
        'src/app.js': "import { toast } from './applix-ui.js';",
      });
      final files = project.injectionFiles();
      final manifest = jsonDecode(files['app.json']!) as Map<String, dynamic>;
      expect((manifest['uiKit'] as Map)['js'], 'applix-ui.js');
      expect(files['src/app.js'], contains("'./applix-ui.js'"));
    });
  });
}
