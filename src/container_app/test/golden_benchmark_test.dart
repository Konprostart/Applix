import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:applix/services/golden_benchmark.dart';

const _paths = {
  'budget': 'test/fixtures/golden/budget.html',
  'fitness': 'test/fixtures/golden/fitness.html',
  'tasks': 'assets/starters/todo.html',
};

void main() {
  group('Golden benchmark', () {
    test('the three standard briefs are defined once', () {
      expect(GoldenBenchmark.briefs.map((b) => b.id).toList(),
          ['budget', 'fitness', 'tasks']);
      for (final brief in GoldenBenchmark.briefs) {
        expect(GoldenBenchmark.brief(brief.id), same(brief));
        expect(brief.prompt.length, greaterThan(40));
      }
    });

    for (final entry in _paths.entries) {
      test('${entry.key} fixture passes every rule', () {
        final html = File(entry.value).readAsStringSync();
        final brief = GoldenBenchmark.brief(entry.key)!;
        final failures = GoldenBenchmark.evaluate(html, brief);
        expect(failures, isEmpty,
            reason: '${brief.title}: ${failures.join('; ')}');
      });
    }

    test('validator catches missing seed data, kit and persistence', () {
      final html = File(_paths['budget']!).readAsStringSync();
      final broken = html
          .replaceAll('SEED', 'DATA')
          .replaceAll('iappyx.save', 'saveIt')
          .replaceAll('iappyx.load', 'loadIt')
          .replaceAll('ax-row', 'plain-row');
      final failures = GoldenBenchmark.evaluate(
          broken, GoldenBenchmark.brief('budget')!);
      final rules = failures.map((f) => f.rule).toSet();
      expect(rules, containsAll(['seed', 'persistence', 'ui-kit']));
    });

    test('validator catches placeholder copy and a missing chart', () {
      final html = File(_paths['budget']!).readAsStringSync();
      final broken = html.replaceAll('<div class="ax-chart budget-bars"', '<div class="rows"')
          + '<p>Coming soon</p>';
      final failures = GoldenBenchmark.evaluate(
          broken, GoldenBenchmark.brief('budget')!);
      final rules = failures.map((f) => f.rule).toSet();
      expect(rules, containsAll(['placeholder', 'visualisation']));
    });

    test('report lists every brief', () {
      final lines = GoldenBenchmark.report({
        'budget': [const GoldenFailure('seed', 'none')],
      });
      expect(lines, contains('budget: 1 failure(s)'));
      expect(lines, contains('fitness: pass'));
      expect(lines, contains('tasks: pass'));
    });
  });
}
