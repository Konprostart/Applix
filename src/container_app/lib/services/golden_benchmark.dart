// MIT License
//
// Copyright (c) 2026 iappyx
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

/// The golden benchmark: three standard briefs that every prompt or model
/// change must keep passing.
///
/// This is a structural regression metric, not a model-quality claim: it checks
/// the parts the platform can guarantee (kit usage, seed data, persistence,
/// no developer text) on known-good fixture outputs. The WebView runtime probe
/// separately checks that those fixtures boot.
library;

class GoldenBrief {
  final String id;
  final String title;
  final String prompt;
  final List<String> requiredClasses;
  final bool needsPersistence;
  final bool needsChart;
  final int minControls;

  const GoldenBrief({
    required this.id,
    required this.title,
    required this.prompt,
    required this.requiredClasses,
    this.needsPersistence = true,
    this.needsChart = false,
    this.minControls = 3,
  });
}

class GoldenFailure {
  final String rule;
  final String detail;

  const GoldenFailure(this.rule, this.detail);

  @override
  String toString() => '$rule: $detail';
}

class GoldenBenchmark {
  static const briefs = <GoldenBrief>[
    GoldenBrief(
      id: 'budget',
      title: 'Budget tracker',
      prompt: 'Build a monthly budget tracker with categories, seeded '
          'transactions, a running balance, a chart and add/delete.',
      requiredClasses: [
        'ax-card',
        'ax-row',
        'ax-num',
        'ax-empty',
        'ax-input',
        'ax-btn',
      ],
      needsChart: true,
    ),
    GoldenBrief(
      id: 'fitness',
      title: 'Fitness notes',
      prompt: 'Build a workout log with seeded sessions, type filters, notes, '
          'duration totals and add/delete with persistence.',
      requiredClasses: ['ax-card', 'ax-row', 'ax-chip', 'ax-empty', 'ax-input'],
    ),
    GoldenBrief(
      id: 'tasks',
      title: 'Task list with persistence',
      prompt: 'Build a task list with seeded tasks, open/done filters, '
          'completion toggles, delete and persistence.',
      requiredClasses: ['ax-check', 'ax-row', 'ax-empty', 'ax-input', 'ax-btn'],
      minControls: 4,
    ),
  ];

  static GoldenBrief? brief(String id) {
    for (final b in briefs) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Empty when [html] satisfies [brief], otherwise one entry per broken rule.
  static List<GoldenFailure> evaluate(String html, GoldenBrief brief) {
    final failures = <GoldenFailure>[];
    final lower = html.toLowerCase();

    void require(bool ok, String rule, String detail) {
      if (!ok) failures.add(GoldenFailure(rule, detail));
    }

    require(html.length >= 2000, 'size', 'the app is too small to be usable');
    require(lower.contains('<!doctype html>'), 'doctype', 'missing doctype');
    require(lower.contains('<meta name="viewport"'), 'viewport',
        'missing viewport meta');
    require(lower.contains('viewport-fit=cover'), 'viewport',
        'viewport must use viewport-fit=cover');
    require(lower.contains('theme-color'), 'theme',
        'missing theme-color meta');
    require(lower.contains('system-ui'), 'font',
        'must use the Android system font stack');
    require(!lower.contains('-apple-system'), 'font',
        'must not use the iOS font stack');
    require(lower.contains('var(--ax-'), 'tokens',
        'the app does not use UI kit tokens');
    require(lower.contains('ax-'), 'ui-kit',
        'the app does not use the UI kit');

    for (final cls in brief.requiredClasses) {
      final pattern = RegExp('class=["\'][^"\']*\\b${RegExp.escape(cls)}\\b');
      require(pattern.hasMatch(html), 'ui-kit',
          'missing required component .$cls');
    }

    require(RegExp(r'\bSEED\b').hasMatch(html), 'seed',
        'no seed records (SEED) for first launch');
    final placeholder = RegExp(r'lorem ipsum|coming soon|sample text|feature 1',
        caseSensitive: false);
    require(!placeholder.hasMatch(html) && !RegExp(r'\bTODO\b').hasMatch(html),
        'placeholder', 'contains placeholder copy');

    final controls = RegExp(r'<(button|input|select|textarea)\b',
            caseSensitive: false)
        .allMatches(html)
        .length;
    require(controls >= brief.minControls, 'controls',
        'only $controls controls; expected at least ${brief.minControls}');

    if (brief.needsPersistence) {
      require(html.contains('iappyx.save'), 'persistence',
          'changes are not saved with iappyx.save');
      require(html.contains('iappyx.load'), 'persistence',
          'saved data is not restored with iappyx.load');
    }

    if (brief.needsChart) {
      require(
          lower.contains('<canvas') ||
              lower.contains('sparkline') ||
              lower.contains('barchart') ||
              lower.contains('donut') ||
              lower.contains('ax-chart'),
          'visualisation',
          'a data app needs a chart or sparkline');
    }

    return failures;
  }

  static String report(Map<String, List<GoldenFailure>> failuresByBrief) {
    final lines = <String>[];
    for (final brief in briefs) {
      final failures = failuresByBrief[brief.id] ?? const <GoldenFailure>[];
      lines.add(failures.isEmpty
          ? '${brief.id}: pass'
          : '${brief.id}: ${failures.length} failure(s)');
    }
    return lines.join('\n');
  }
}
