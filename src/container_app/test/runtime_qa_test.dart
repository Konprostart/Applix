import 'package:flutter_test/flutter_test.dart';
import 'package:applix/services/runtime_probe.dart';
import 'package:applix/services/runtime_qa.dart';

RuntimeReport _report({List<String> errors = const [], bool blank = false}) =>
    RuntimeReport.fromJson({
      'ready': true,
      'loaded': true,
      'domReady': true,
      'textLength': blank ? 0 : 80,
      'interactive': blank ? 0 : 3,
      'bodyChildren': blank ? 0 : 2,
      'visuals': 0,
      'errors': errors,
    });

void main() {
  group('RuntimeQa', () {
    test('passes a clean report', () async {
      final outcome = await RuntimeQa.verify(() async => _report());
      expect(outcome.blocked, isFalse);
      expect(outcome.passed, isTrue);
      expect(outcome.message, contains('without JavaScript errors'));
    });

    test('blocks a fatal startup error', () async {
      final outcome = await RuntimeQa.verify(
          () async => _report(errors: ['TypeError: app is not defined']));
      expect(outcome.blocked, isTrue);
      expect(outcome.passed, isFalse);
      expect(outcome.message, contains('TypeError'));
    });

    test('blocks a blank screen', () async {
      final outcome = await RuntimeQa.verify(() async => _report(blank: true));
      expect(outcome.blocked, isTrue);
      expect(outcome.message, contains('blank'));
    });

    test('blocks a cancelled check', () async {
      final outcome = await RuntimeQa.verify(() async => null);
      expect(outcome.cancelled, isTrue);
      expect(outcome.blocked, isTrue);
    });

    test('does not block inconclusive reports', () async {
      final inconclusive = await RuntimeQa.verify(
          () async => RuntimeReport.inconclusive('no report'));
      expect(inconclusive.blocked, isFalse);
      expect(inconclusive.passed, isFalse);
    });

    test('blocks a real module resolution failure', () async {
      final modules = await RuntimeQa.verify(() async => _report(errors: [
            'Failed to resolve module specifier "./ui.js"',
          ]));
      expect(modules.blocked, isTrue);
    });

    test('does not turn a verifier exception into a false failure', () async {
      final outcome = await RuntimeQa.verify(() async => throw StateError('no WebView'));
      expect(outcome.blocked, isFalse);
      expect(outcome.message, contains('unavailable'));
    });

    test('evaluate maps a report without running anything', () {
      final outcome = RuntimeQa.evaluate(_report());
      expect(outcome.blocked, isFalse);
      expect(outcome.report, isNotNull);
    });
  });
}
