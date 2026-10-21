/// Stable, per-app origin for the in-app preview WebView.
///
/// `loadHtmlString` needs a base URL. Reusing `https://localhost/` for every
/// app made localStorage/IndexedDB leak between generated apps, so the host is
/// derived from the document and its project files.
library;

class PreviewOrigin {
  static String baseUrl(String html, Map<String, String> files) {
    final hash = _fnv1a(html, files);
    return 'https://app-${hash.toRadixString(16).padLeft(8, '0')}.localhost/';
  }

  static int _fnv1a(String html, Map<String, String> files) {
    var hash = 0x811c9dc5;
    void add(String value) {
      for (var i = 0; i < value.length; i++) {
        hash ^= value.codeUnitAt(i);
        hash = (hash * 0x01000193) & 0xFFFFFFFF;
      }
      // Domain separator, so {"a":"bc"} and {"ab":"c"} differ.
      hash ^= 0x1f;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }

    add(html);
    final keys = files.keys.toList()..sort();
    for (final key in keys) {
      add(key);
      add(files[key] ?? '');
    }
    return hash;
  }
}
