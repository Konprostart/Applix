/// Extracts the app HTML out of an AI response.
///
/// Models keep talking around the app even when the prompt forbids it:
/// they write "Here is your app", wrap the code in fences, and after the
/// closing tag they append a "Summary of changes made" list. That prose must
/// never reach the app screen - the WebView renders anything after `</html>`
/// as body text. This extractor never trusts the prose: it takes the document
/// and hard-truncates at `</html>`.
library;

class AiResponse {
  /// Returns the largest usable piece of the app document inside [text],
  /// or '' when the response does not contain HTML at all.
  static String extractAppHtml(String text) {
    var s = text
        .replaceAll('\ufeff', '')
        .replaceAll('\u200b', '')
        .trim();
    if (s.isEmpty) return '';

    // 1) The response may contain several fenced blocks (notes, logs, ...).
    //    The app is the first fence that starts like an HTML document.
    final fencePattern = RegExp(r'```[a-zA-Z0-9]*[^\n]*\n([\s\S]*?)```');
    for (final fence in fencePattern.allMatches(s)) {
      final inner = fence.group(1)!.trim();
      final l = inner.toLowerCase();
      if (l.startsWith('<!doctype') || l.startsWith('<html')) {
        s = inner;
        break;
      }
    }

    // 2) No usable fence: slice from the document start. The first '<' is not
    //    a safe cut point - the prose often mentions `<input>` or `<div>`,
    //    which would corrupt the document.
    final lower2 = s.toLowerCase();
    final doctype = lower2.indexOf('<!doctype');
    final htmlTag = lower2.indexOf('<html');
    // Prefer the doctype even when prose earlier mentioned `<html>` — that
    // mention used to make the parser start inside a sentence.
    final start = doctype >= 0 ? doctype : htmlTag;
    if (start >= 0) s = s.substring(start);

    // 3) Prefer the real document end. Everything after `</html>` is chat
    //    prose ("Summary of changes made...") - drop it. Models forget the
    //    closing tag often enough that rejecting the whole answer makes the
    //    app unusable, so salvaging is better than failing generation.
    final l3 = s.toLowerCase();
    final end = l3.lastIndexOf('</html>');
    if (end >= 0) {
      s = s.substring(0, end + '</html>'.length).trim();
    } else {
      s = _salvageHtml(s);
      if (s.isEmpty) return '';
    }

    // 4) Only an actual, complete document counts.
    final l4 = s.toLowerCase();
    if (!l4.startsWith('<!doctype') && !l4.startsWith('<html')) return '';
    return s;
  }

  /// Last-resort HTML salvage when the response has no `</html>` tail:
  /// strip trailing code fences and prose-only lines, then emit the best HTML
  /// prefix left. Bad enough output still comes back empty, which is handled
  /// by the normal parser fallback.
  static String _salvageHtml(String s) {
    final lines = s.split('\n');
    while (lines.isNotEmpty) {
      final t = lines.last.trim();
      if (t.isEmpty ||
          t == '```' ||
          t.startsWith('Note:') ||
          t.startsWith('Notes:') ||
          t.startsWith('Summary') ||
          t.startsWith('- ') ||
          t.startsWith('* ') ||
          t.startsWith('This app') ||
          t.startsWith('Okay,') ||
          t.startsWith('Sure,') ||
          t.startsWith('Here is') ||
          t.startsWith('Here')) {
        lines.removeLast();
      } else {
        break;
      }
    }
    final out = lines.join('\n').trim();
    // A response of only fences/prose is not an app.
    if (out.length < 8) return '';
    // If there is no markup left at all, it's prose.
    if (!RegExp(r'<[!h]').hasMatch(out.toLowerCase())) return '';
    return out;
  }
}
