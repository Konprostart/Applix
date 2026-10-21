/// Static "does this look like a native app?" audit for generated HTML.
///
/// The rules are deliberately conservative: they only flag things that are
/// clearly wrong, so a false positive never makes an app worse.
library;

import 'dev_text_sanitizer.dart';

class UiViolation {
  final String code;
  final String message;

  const UiViolation(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

class UiAuditor {
  static final RegExp _headingPattern =
      RegExp(r'<h([1-6])(\s[^>]*)?>([\s\S]*?)</h\1\s*>', caseSensitive: false);

  /// Audits an HTML document and returns the violations that were found.
  static List<UiViolation> audit(String html) {
    final issues = <UiViolation>[];
    if (html.trim().isEmpty) return issues;

    final lower = html.toLowerCase();
    final hasViewport = lower.contains('name="viewport"') || lower.contains("name='viewport'");
    final viewportBlock = _metaContent(lower, 'viewport');

    if (!hasViewport) {
      issues.add(const UiViolation(
          'viewport', 'Missing <meta name="viewport"> - the app will not fit the screen.'));
    } else if (!viewportBlock.contains('viewport-fit=cover')) {
      issues.add(const UiViolation('viewport-fit',
          'The viewport meta needs viewport-fit=cover so the app can draw around notches.'));
    }

    if (hasViewport && !viewportBlock.contains('user-scalable=no')) {
      issues.add(const UiViolation(
          'user-scalable', 'Add user-scalable=no to the viewport - native apps do not pinch-zoom.'));
    }

    if (!lower.contains('name="theme-color"') && !lower.contains("name='theme-color'")) {
      issues.add(const UiViolation('theme-color',
          'Add <meta name="theme-color" content="#0d0d1a"> so the system bars match the app.'));
    }

    if (lower.contains('-apple-system') && !lower.contains('system-ui')) {
      issues.add(const UiViolation('font',
          'Use the Android font stack (system-ui, Roboto) instead of -apple-system.'));
    }

    // A developer text (changelog, "what's new", release notes) is never part
    // of the app the user sees. The same text is removed deterministically
    // before the app is built - see DevTextSanitizer.
    for (final match in _headingPattern.allMatches(html)) {
      if (isDevText(match.group(3) ?? '')) {
        issues.add(const UiViolation(
          'developer-text',
          'The app contains a developer text (changelog, release notes or a '
              'list of changes) - it must not be part of the app the user sees.',
        ));
        break;
      }
    }

    if (!lower.contains('ax-')) {
      issues.add(const UiViolation('ui-kit',
          'The app does not use the Applix UI Kit classes - build it from .ax-* components.'));
    }

    if (lower.contains('<button') &&
        !lower.contains('ax-btn') &&
        !lower.contains('min-height') &&
        !lower.contains('min-height:44') &&
        !lower.contains('min-height:48')) {
      issues.add(const UiViolation('touch-target',
          'Buttons need a 48px touch target - use the .ax-btn class.'));
    }

    if (lower.contains('<input') &&
        !lower.contains('ax-input') &&
        !lower.contains('ax-field')) {
      issues.add(const UiViolation('input',
          'Text inputs should use the .ax-input class for consistent styling.'));
    }

    if (lower.contains('position:fixed') &&
        lower.contains('top:0') &&
        !lower.contains('safe-area-inset') &&
        !lower.contains('--ax-safe-top')) {
      issues.add(const UiViolation('safe-area',
          'A fixed element sits at top:0 - pad it with var(--ax-safe-top) so it is not under the status bar.'));
    }

    if (!lower.contains('ax-empty') &&
        (lower.contains('innerhtml') || lower.contains('appendchild')) &&
        !lower.contains('ax-skeleton')) {
      issues.add(const UiViolation('states',
          'Add empty and loading states (.ax-empty, .ax-skeleton) - native apps always have them.'));
    }

    return issues;
  }

  static String _metaContent(String lowerHtml, String name) {
    final idx = lowerHtml.indexOf('name="$name"');
    if (idx == -1) return '';
    final contentIdx = lowerHtml.indexOf('content=', idx);
    if (contentIdx == -1) return '';
    var end = lowerHtml.indexOf('>', contentIdx);
    if (end == -1) end = lowerHtml.length;
    return lowerHtml.substring(contentIdx, end);
  }

  /// Formats the violations for an AI repair prompt.
  static String formatIssues(List<UiViolation> issues) {
    if (issues.isEmpty) return '';
    final buffer = StringBuffer();
    for (final issue in issues) {
      buffer.writeln('- ${issue.message}');
    }
    return buffer.toString();
  }

  /// The instruction block used for the automatic polish pass.
  static String buildPolishMessage(List<UiViolation> issues) {
    final buffer = StringBuffer();
    buffer.writeln('The app you produced does not look like a native Android app yet.');
    buffer.writeln('Fix exactly these problems, keep every feature and every bridge call working,');
    buffer.writeln('and return the complete updated HTML file:');
    buffer.writeln();
    buffer.write(formatIssues(issues));
    return buffer.toString();
  }
}
