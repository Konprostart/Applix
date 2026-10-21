import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:applix/services/runtime_probe.dart';

Map<String, dynamic> _json({
  bool ready = true,
  int textLength = 40,
  int interactive = 2,
  int bodyChildren = 2,
  int visuals = 0,
  List<String> errors = const [],
}) =>
    {
      'ready': ready,
      'loaded': true,
      'domReady': true,
      'textLength': textLength,
      'interactive': interactive,
      'bodyChildren': bodyChildren,
      'visuals': visuals,
      'errors': errors,
    };

void main() {
  group('RuntimeReport', () {
    test('passes a rendered app without errors', () {
      final report = RuntimeReport.fromJson(_json());
      expect(report.fatal, isFalse);
      expect(report.passed, isTrue);
    });

    test('fails on an uncaught error', () {
      final report = RuntimeReport.fromJson(
          _json(errors: ['TypeError: cannot read properties of null']));
      expect(report.fatal, isTrue);
      expect(report.fatalErrors, hasLength(1));
    });

    test('ignores benign resize noise', () {
      final report = RuntimeReport.fromJson(_json(errors: [
        'ResizeObserver loop completed with undelivered notifications.',
      ]));
      expect(report.fatal, isFalse);
    });

    test('a missing project file is fatal, not hidden as noise', () {
      final report = RuntimeReport.fromJson(
          _json(errors: ['net::ERR_FILE_NOT_FOUND']));
      expect(report.fatal, isTrue);
    });

    test('fails on a blank screen', () {
      final report = RuntimeReport.fromJson(
          _json(textLength: 0, interactive: 0, bodyChildren: 0));
      expect(report.blank, isTrue);
      expect(report.fatal, isTrue);
      expect(report.summary, contains('blank'));
    });

    test('does not call an empty canvas app blank', () {
      final report = RuntimeReport.fromJson(
          _json(textLength: 0, interactive: 0, bodyChildren: 1, visuals: 1));
      expect(report.blank, isFalse);
      expect(report.fatal, isFalse);
    });

    test('treats module resolution as a real crash', () {
      final report = RuntimeReport.fromJson(_json(errors: [
        'Failed to resolve module specifier "./ui.js"',
      ]));
      expect(report.fatal, isTrue);
      expect(report.fatalErrors, hasLength(1));
    });

    test('inconclusive is never fatal', () {
      final report = RuntimeReport.inconclusive('no report');
      expect(report.fatal, isFalse);
      expect(report.passed, isFalse);
    });

    test('parses the quoted string returned by the WebView', () {
      final raw = jsonEncode(jsonEncode(_json()));
      final report = RuntimeReport.parse(raw);
      expect(report, isNotNull);
      expect(report!.ready, isTrue);
      expect(report.textLength, 40);
    });

    test('parses an object-like string too', () {
      final report = RuntimeReport.parse(jsonEncode(_json()));
      expect(report, isNotNull);
      expect(report!.interactive, 2);
    });

    test('returns null for an empty WebView result', () {
      expect(RuntimeReport.parse(''), isNull);
      expect(RuntimeReport.parse('""'), isNull);
    });
  });

  group('RuntimeProbe', () {
    test('installs the probe after the head tag', () {
      final out = RuntimeProbe.inject('<html><head><title>x</title></head><body></body></html>');
      final headEnd = out.indexOf('>', out.indexOf('<head')) + 1;
      final probe = out.indexOf('window.__applixRuntime');
      final title = out.indexOf('<title>');
      expect(probe, greaterThan(headEnd));
      expect(probe, lessThan(title));
    });

    test('injects at the start when there is no head', () {
      final out = RuntimeProbe.inject('<html><body>x</body></html>');
      expect(out.startsWith('<script>'), isTrue);
    });

    test('captures boot errors and unhandled rejections', () {
      expect(RuntimeProbe.bootstrap, contains("addEventListener('error'"));
      expect(RuntimeProbe.bootstrap, contains('unhandledrejection'));
      expect(RuntimeProbe.bootstrap, contains('bodyChildren'));
      expect(RuntimeProbe.bootstrap, contains('console.error'));
    });
  });
}
