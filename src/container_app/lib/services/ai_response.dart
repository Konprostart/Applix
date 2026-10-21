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

    // 3) Hard stop at the real document end. Everything after `</html>` is
    //    chat prose ("Summary of changes made...") - drop it.
    final l3 = s.toLowerCase();
    final end = l3.lastIndexOf('</html>');
    // A missing closing tag means the provider stopped at max_tokens or the
    // connection died. Never accept a truncated document as a finished app.
    if (end < 0) return '';
    s = s.substring(0, end + '</html>'.length).trim();

    // 4) Only an actual, complete document counts.
    final l4 = s.toLowerCase();
    if (!l4.startsWith('<!doctype') && !l4.startsWith('<html')) return '';
    return s;
  }
}
