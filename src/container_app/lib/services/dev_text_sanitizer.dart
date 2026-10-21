/// Removes developer texts from a generated app.
///
/// An app belongs to the end user, not to the developer: a changelog, a
/// "what's new" list, release notes or a version history must never be part
/// of the app (and therefore never end up inside the APK).
///
/// The removal is deterministic - it does not depend on the AI polishing the
/// code - so a generated app is always clean, even if the model ignores the
/// instructions in the system prompt.
library;

/// The headings that mark a developer text.
///
/// Only unambiguous developer headings are listed: "release notes" is left out
/// on purpose, because a show or a product can have release notes of its own
/// that belong into the app.
const List<String> devTextHeadings = [
  'changes and improvements',
  'changes and improvement',
  "what's new",
  'whats new',
  'changelog',
  'change log',
  'version history',
  'new in this version',
  'what is new',
];

final RegExp _headingPattern =
    RegExp(r'<h([1-6])(\s[^>]*)?>([\s\S]*?)</h\1\s*>', caseSensitive: false);

final RegExp _tagPattern = RegExp(r'<[^>]*>');

/// True when the text is a developer text (heading or short block).
bool isDevText(String text) {
  final clean = text
      .replaceAll(_tagPattern, ' ')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
  if (clean.isEmpty) return false;
  // A heading that only says "Improvements" is a developer text as well, but
  // only when it is short - a long paragraph is probably real app content.
  if (clean.length > 40) return false;
  for (final heading in devTextHeadings) {
    if (clean == heading) return true;
    if (clean.startsWith('$heading ') || clean.startsWith('$heading:')) {
      return true;
    }
  }
  return false;
}

/// Removes developer text sections from an HTML document.
String removeDevText(String html) {
  var result = html;
  // Repeat: one removal can expose the next one.
  for (var pass = 0; pass < 5; pass++) {
    final changed = _removeOneSection(result);
    if (changed == result) break;
    result = changed;
  }
  result = _removeLooseBlocks(result);
  return result;
}

String _removeOneSection(String html) {
  final headings = _headingPattern.allMatches(html).toList();
  for (var i = 0; i < headings.length; i++) {
    final match = headings[i];
    if (!isDevText(match.group(3) ?? '')) continue;
    final level = int.tryParse(match.group(1) ?? '') ?? 6;
    // The section ends at the next heading of the same or a higher level.
    var end = html.length;
    for (var j = i + 1; j < headings.length; j++) {
      final nextLevel = int.tryParse(headings[j].group(1) ?? '') ?? 6;
      if (nextLevel <= level) {
        end = headings[j].start;
        break;
      }
    }
    return html.substring(0, match.start) + html.substring(end);
  }
  return html;
}

/// Removes a standalone paragraph or list item that is nothing but a
/// developer text (the AI sometimes writes it without a heading).
String _removeLooseBlocks(String html) {
  final blockPattern =
      RegExp(r'<(p|li|div)(\s[^>]*)?>[\s\S]*?<\/\1\s*>', caseSensitive: false);
  var result = html;
  for (var pass = 0; pass < 5; pass++) {
    final matches = blockPattern.allMatches(result).toList();
    var changed = false;
    for (final match in matches.reversed) {
      final inner = match.group(0) ?? '';
      final text = inner.replaceFirst(RegExp(r'^<[^>]*>'), '');
      // Only a short block that is entirely a developer text.
      if (text.length < 80 && isDevText(text)) {
        result = result.substring(0, match.start) + result.substring(match.end);
        changed = true;
      }
    }
    if (!changed) break;
  }
  return result;
}

/// The public entry points, used by the preview, the editor, the build and
/// the visual check.
class DevTextSanitizer {
  /// Removes every developer text section from an HTML document.
  static String removeDevText(String html) => removeDevText(html);

  /// True when the text is a developer text.
  static bool isDevText(String text) => isDevText(text);
}
