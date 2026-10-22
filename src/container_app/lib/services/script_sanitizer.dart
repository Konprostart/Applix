/// Keeps generated scripts valid for the classic `<script>` they run in.
///
/// Models sometimes write ES module syntax (`export function ...`, or load
/// `applix-ui.js` - which is a module - with a plain `<script src>`). The
/// browser then fails with `Uncaught SyntaxError: Unexpected token 'export'`
/// and no button gets wired up.
///
/// Rules applied to every model answer, every preview load and every build:
///   * a classic script that still contains `export` loses the keyword - the
///     declarations stay global, so inline handlers keep working;
///   * a classic script that needs `import`, or a classic `<script src>` that
///     points at a module, is switched to `type="module"` and followed by a
///     small glue module that exposes its exports on `window`, so classic code
///     can still call them.
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
  static final RegExp _identImport =
      RegExp(r'''(^|[;{}()\s])import\s*["']''', multiLine: true);
  static final RegExp _identImportFrom = RegExp(
      r'''(^|[;{}()\s])import\s+[^;\n]*\bfrom\s*["']''',
      multiLine: true);
  static final RegExp _exportToken =
      RegExp(r'''(^|[^\w$])export\b''', caseSensitive: false);

  static bool hasImports(String code) =>
      _identImport.hasMatch(code) || _identImportFrom.hasMatch(code);

  static bool hasExports(String code) => _exportToken.hasMatch(code);

  /// Removes module export syntax, keeping the declarations themselves.
  ///
  /// The scan is literal-aware: `export` inside strings, template literals or
  /// comments is left alone.
  static String stripExports(String code) {
    if (!code.contains('export')) return code;
    final out = StringBuffer();
    var i = 0;
    final n = code.length;

    while (i < n) {
      final c = code[i];
      if (c == '/' && i + 1 < n && code[i + 1] == '/') {
        final end = code.indexOf('\n', i);
        final stop = end == -1 ? n : end;
        out.write(code.substring(i, stop));
        i = stop;
        continue;
      }
      if (c == '/' && i + 1 < n && code[i + 1] == '*') {
        final end = code.indexOf('*/', i + 2);
        final stop = end == -1 ? n : end + 2;
        out.write(code.substring(i, stop));
        i = stop;
        continue;
      }
      if (c == '"' || c == '\'') {
        final pad = _stringStart(code, i, quoted: true);
        out.write(code.substring(i, pad));
        i = pad;
        continue;
      }
      if (c == '`') {
        final end = _templateEnd(code, i);
        out.write(code.substring(i, end));
        i = end;
        continue;
      }
      if ((c == 'e' || c == 'E') &&
          code.startsWith('export', i) &&
          (i == 0 || !_isIdent(code.codeUnitAt(i - 1))) &&
          (i + 6 >= n || !_isIdent(code.codeUnitAt(i + 6)))) {
        final after = _skipBlank(code, i + 6);
        final word = _word(code, after);
        if (word == 'default') {
          final exprStart = _skipBlank(code, after + 7);
          final next = _word(code, exprStart);
          if (next == 'function' ||
              next == 'class' ||
              next == 'async' ||
              next.startsWith('function*')) {
            i = after + 7;
          } else {
            out.write('var defaultExport = ');
            i = exprStart;
          }
        } else if (word.startsWith('{')) {
          i = _afterBalanced(code, after, '{', '}');
          i = _skipStatementEnd(code, i);
        } else if (word.startsWith('*')) {
          i = _skipStatementEnd(code, after);
        } else {
          i = after;
        }
        continue;
      }
      out.write(c);
      i++;
    }
    return out.toString();
  }

  /// Normalizes every classic script of [html] and of the project [files]
  /// (paths relative to the entry, e.g. `src/app.js`).
  static ScriptNormalization normalize(String html, Map<String, String> files) {
    final updated = Map<String, String>.from(files);
    final out = StringBuffer();
    var last = 0;
    for (final m in _scriptTag.allMatches(html)) {
      out.write(html.substring(last, m.start));
      last = m.end;
      final whole = m.group(0)!;
      final attrs = m.group(1) ?? '';
      final body = m.group(2) ?? '';
      if (_moduleAttr.hasMatch(attrs)) {
        out.write(whole);
        continue;
      }

      final src = _srcOf(attrs)?.trim();
      if (src != null && src.isNotEmpty) {
        final key = _fileKey(src, updated);
        if (key != null) {
          final code = updated[key]!;
          if (hasImports(code)) {
            out.write(_asModule(whole));
            out.write(_glue(src));
            continue;
          }
          if (hasExports(code)) {
            // Declarations stay global once `export` is gone, so the tag can
            // remain a classic script.
            updated[key] = stripExports(code);
          }
        }
        out.write(whole);
        continue;
      }

      if (hasImports(body)) {
        out.write(_asModule(whole));
        continue;
      }
      if (hasExports(body)) {
        out.write(whole.replaceFirst(body, stripExports(body)));
        continue;
      }
      out.write(whole);
    }
    out.write(html.substring(last));
    return ScriptNormalization(bindInlineHandlers(out.toString()), updated);
  }

  static final RegExp _inlineHandlerCall = RegExp(
      r'''\bon[a-z]+\s*=\s*["']\s*([A-Za-z_$][\w$]*)\s*\(''',
      caseSensitive: false);

  /// Makes functions that inline handlers call reachable from `window`.
  ///
  /// For every `onclick="name(...)"`-style call, a guarded `window.name = name`
  /// runs after the document's scripts. A top-level declaration becomes global;
  /// a name that only exists inside a closure is skipped (the guard catches the
  /// ReferenceError), so the document is never broken by this step.
  static String bindInlineHandlers(String html) {
    if (html.contains('id="applix-handler-bind"')) return html;
    final names = _inlineHandlerCall
        .allMatches(html)
        .map((m) => m.group(1)!)
        .where((n) => !const {'this', 'event', 'return', 'if', 'javascript'}.contains(n))
        .toSet();
    if (names.isEmpty) return html;
    final bindings = StringBuffer('<script id="applix-handler-bind">\n');
    for (final name in names) {
      bindings.write('try{window.$name = $name;}catch(e){}\n');
    }
    bindings.write('</script>');
    final close = html.toLowerCase().lastIndexOf('</body>');
    if (close == -1) return '$html\n$bindings';
    return html.substring(0, close) + bindings.toString() + '\n' + html.substring(close);
  }

  /// Sanitizes a document without knowing its project files. Used as a final
  /// pass right before the HTML is served or packaged.
  static String normalizeDocument(String html) => normalize(html, const {}).html;

  static String _glue(String specifier) {
    final safe = specifier.replaceAll('"', '%22');
    return '<script type="module">\n'
        'import * as __applixModule from "$safe";\n'
        'try{\n'
        '  window.__applixModules=window.__applixModules||{};\n'
        '  window.__applixModules["$safe"]=__applixModule;\n'
        '  Object.keys(__applixModule).forEach(function(k){\n'
        '    try{if(!(k in window))window[k]=__applixModule[k];}catch(e){}\n'
        '  });\n'
        '}catch(e){}\n'
        '</script>';
  }

  static bool _isIdent(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x24 ||
      c == 0x5F;

  /// Index just past the string literal that starts at [i].
  static int _stringStart(String code, int i, {required bool quoted}) {
    final quote = code[i];
    var j = i + 1;
    while (j < code.length) {
      final c = code[j];
      if (c == '\\') {
        j += 2;
        continue;
      }
      if (c == quote) return j + 1;
      if (c == '\n') return j;
      j++;
    }
    return code.length;
  }

  /// Index just past the template literal that starts at [i].
  static int _templateEnd(String code, int i) {
    var j = i + 1;
    while (j < code.length) {
      final c = code[j];
      if (c == '\\') {
        j += 2;
        continue;
      }
      if (c == '`') return j + 1;
      if (c == r'$' && j + 1 < code.length && code[j + 1] == '{') {
        j = _afterBalanced(code, j + 2, '{', '}');
        continue;
      }
      j++;
    }
    return code.length;
  }

  static int _skipBlank(String code, int i) {
    var j = i;
    while (j < code.length) {
      final c = code[j];
      if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
        j++;
        continue;
      }
      break;
    }
    return j;
  }

  static String _word(String code, int i) {
    if (i >= code.length) return '';
    final c = code[i];
    if (c == '{' || c == '*') return c;
    var j = i;
    while (j < code.length && (_isIdent(code.codeUnitAt(j)) || code[j] == '*')) {
      j++;
    }
    return code.substring(i, j);
  }

  static int _afterBalanced(String code, int i, String open, String close) {
    var depth = 0;
    var j = i;
    while (j < code.length) {
      final c = code[j];
      if (c == '"' || c == '\'') {
        j = _stringStart(code, j, quoted: true);
        continue;
      }
      if (c == '`') {
        j = _templateEnd(code, j);
        continue;
      }
      if (c == open) depth++;
      if (c == close) {
        depth--;
        if (depth == 0) return j + 1;
      }
      j++;
    }
    return code.length;
  }

  static int _skipStatementEnd(String code, int i) {
    var j = i;
    var depth = 0;
    while (j < code.length) {
      final c = code[j];
      if (c == '"' || c == '\'') {
        j = _stringStart(code, j, quoted: true);
        continue;
      }
      if (c == '`') {
        j = _templateEnd(code, j);
        continue;
      }
      if (c == '{') depth++;
      if (c == '}') depth--;
      if (c == ';' && depth <= 0) return j + 1;
      if (c == '\n' && depth <= 0) return j;
      j++;
    }
    return code.length;
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
    final cut = path.indexOf('?');
    if (cut != -1) path = path.substring(0, cut);
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
