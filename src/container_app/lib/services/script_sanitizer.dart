/// Keeps generated scripts valid for the classic `<script>` they run in.
///
/// Models sometimes write ES module syntax (`export function ...`) into a file
/// that the HTML loads as a plain script. The browser then fails with
/// `Uncaught SyntaxError: Unexpected token 'export'` and the buttons never
/// get wired up. This normalizer runs on every model answer and on every
/// preview load:
///   * a classic script with `export` statements loses the `export` keywords
///     (declarations stay global, so inline handlers keep working);
///   * a script that uses `import` is switched to `type="module"`, because
///     only modules may import.
library;

class ScriptNormalization {
  final String html;
  final Map<String, String> files;

  const ScriptNormalization(this.html, this.files);
}

class ScriptSanitizer {
  static final RegExp _scriptTag =
      RegExp(r'<script\b([^>]*)>([\s\S]*?)</script>', caseSensitive: false);
  static final RegExp _srcAttr = RegExp(
      r'''\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
      caseSensitive: false);
  static final RegExp _moduleAttr =
      RegExp(r'''\btype\s*=\s*["']?module["']?''', caseSensitive: false);
  static final RegExp _typeAttr = RegExp(
      r'''\s+type\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)''',
      caseSensitive: false);
  static final RegExp _exportAny = RegExp(r'^[ \t]*export\s', multiLine: true);
  static final RegExp _importStmt =
      RegExp(r'''^[ \t]*import\s[^;\n]*?["']''', multiLine: true);
  static final RegExp _exportDefaultDecl = RegExp(
      r'^(\s*)export\s+default\s+(?=(?:async\s+)?(?:function|class)\b)',
      multiLine: true);
  static final RegExp _exportDefaultExpr =
      RegExp(r'^(\s*)export\s+default\s+', multiLine: true);
  static final RegExp _exportDecl = RegExp(
      r'^(\s*)export\s+(?=(?:async\s+)?(?:function\*?|const|let|var|class)\b)',
      multiLine: true);
  static final RegExp _exportList = RegExp(
      r'''^[ \t]*export\s*\{[^}]*\}\s*(?:from\s*(?:"[^"\n]*"|'[^'\n]*'))?[ \t]*;?[ \t]*$''',
      multiLine: true);

  /// True when [code] has an `export` statement at the start of a line.
  static bool hasExports(String code) => _exportAny.hasMatch(code);

  /// True when [code] has an `import` statement (`import x from '...'`).
  static bool hasImports(String code) => _importStmt.hasMatch(code);

  /// Removes module export syntax, keeping the declarations themselves.
  static String stripExports(String code) {
    var out = code.replaceAllMapped(_exportDefaultDecl, (m) => m.group(1)!);
    out = out.replaceAllMapped(
        _exportDefaultExpr, (m) => '${m.group(1)}var defaultExport = ');
    out = out.replaceAllMapped(_exportDecl, (m) => m.group(1)!);
    out = out.replaceAll(_exportList, '');
    return out;
  }

  /// Normalizes every classic script of [html] and of the project [files]
  /// (paths relative to the entry, e.g. `src/app.js`).
  static ScriptNormalization normalize(String html, Map<String, String> files) {
    final updated = Map<String, String>.from(files);
    final out = html.replaceAllMapped(_scriptTag, (m) {
      final whole = m.group(0)!;
      final attrs = m.group(1) ?? '';
      final body = m.group(2) ?? '';
      if (_moduleAttr.hasMatch(attrs)) return whole;

      final src = _srcOf(attrs);
      if (src != null) {
        final key = _fileKey(src, updated);
        if (key == null) return whole;
        final code = updated[key]!;
        if (hasImports(code)) return _asModule(whole);
        if (hasExports(code)) updated[key] = stripExports(code);
        return whole;
      }

      if (hasImports(body)) return _asModule(whole);
      if (hasExports(body)) return whole.replaceFirst(body, stripExports(body));
      return whole;
    });
    return ScriptNormalization(out, updated);
  }

  static String? _srcOf(String attrs) {
    final m = _srcAttr.firstMatch(attrs);
    if (m == null) return null;
    return m.group(1) ?? m.group(2) ?? m.group(3);
  }

  static String? _fileKey(String src, Map<String, String> files) {
    var path = src.trim();
    final lower = path.toLowerCase();
    if (lower.startsWith('http:') ||
        lower.startsWith('https:') ||
        lower.startsWith('data:') ||
        lower.startsWith('blob:') ||
        lower.startsWith('//')) {
      return null;
    }
    while (path.startsWith('./')) {
      path = path.substring(2);
    }
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    return files.containsKey(path) ? path : null;
  }

  /// Rewrites the opening tag of a script so it runs as a module.
  static String _asModule(String whole) {
    final close = whole.indexOf('>');
    if (close == -1) return whole;
    final open = whole
        .substring(0, close + 1)
        .replaceAll(_typeAttr, '')
        .replaceFirst(RegExp(r'<script', caseSensitive: false),
            '<script type="module"');
    return open + whole.substring(close + 1);
  }
}
