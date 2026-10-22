// MIT License — Copyright (c) 2026 iappyx

import 'dart:convert';

import 'dev_text_sanitizer.dart';
import 'script_sanitizer.dart';
import 'ai_response.dart';
import 'json_repair.dart';

/// A generated app as a project: an entry HTML file plus modules.
///
/// Phase 2 of the architecture upgrade. A model may answer with a single
/// HTML document (the old behaviour, still the default) or with a project
/// JSON block:
///
/// ```json
/// {"applix":2,"entry":"index.html","name":"Ticker",
///  "routes":["/","/settings"],
///  "files":{"index.html":"<!doctype html>...","src/app.js":"import ..."}}
/// ```
///
/// The project is packaged next to the entry inside `assets/app/`, which the
/// shell serves over the secure origin from Phase 1 - so relative ES module
/// imports work in the installed app. Older single-file apps stay valid:
/// [parseModelOutput] falls back to [AiResponse.extractAppHtml].
class AppProject {
  /// Format marker written into app.json.
  static const format = 2;

  /// The shared design system shipped with every app (Phase 3).
  static const uiKitVersion = 2;
  static const uiKitCss = 'applix-ui.css';
  static const uiKitJs = 'applix-ui.js';

  /// The entry document, relative to the app root.
  final String entry;

  /// Every file of the app, keyed by a relative path (e.g. `src/app.js`).
  final Map<String, String> files;

  /// Optional declared routes, purely metadata for tooling.
  final List<String> routes;

  /// Optional app name from the model (the real name comes from the user).
  final String? name;

  const AppProject({
    this.entry = 'index.html',
    required this.files,
    this.routes = const [],
    this.name,
  });

  /// A plain single-file app (the pre-Phase-2 format).
  factory AppProject.singleFile(String html) =>
      AppProject(files: {'index.html': html});

  bool get isMultiFile => files.length > 1;

  String get entryHtml => files[entry] ?? '';

  /// Parses a model answer into a project.
  ///
  /// Order: a project JSON block first (fenced or bare), then the classic
  /// single HTML document. Never throws: an unusable answer yields an empty
  /// project and the caller shows its normal error path.
  static AppProject parseModelOutput(String response) {
    final decoded = _findProjectJson(response);
    if (decoded != null) {
      final files = <String, String>{};
      final rawFiles = decoded['files'];
      if (rawFiles is Map) {
        rawFiles.forEach((key, value) {
          if (key is! String || value is! String) return;
          final path = safePath(key);
          if (path != null && value.trim().isNotEmpty) files[path] = value;
        });
      }
      if (files.isNotEmpty) {
        final rawEntry = decoded['entry'];
        var entry = rawEntry is String ? safePath(rawEntry) : null;
        if (entry == null || !files.containsKey(entry)) {
          entry = _guessEntry(files);
        }
        if (entry != null) {
          // The packager always writes the entry as assets/app/index.html, so
          // a root-level entry with another name is renamed; a nested entry
          // would break its own relative paths and is rejected by validate().
          if (entry != 'index.html' && !entry.contains('/')) {
            files['index.html'] = files.remove(entry) ?? '';
            entry = 'index.html';
          }
          final routes = <String>[];
          final rawRoutes = decoded['routes'];
          if (rawRoutes is List) {
            for (final r in rawRoutes) {
              if (r is String && r.trim().isNotEmpty) routes.add(r.trim());
            }
          }
          final name = decoded['name'];
          final normalized = ScriptSanitizer.normalize(files[entry] ?? '', files);
          final cleanFiles = Map<String, String>.from(normalized.files)
            ..[entry] = normalized.html;
          return AppProject(
            entry: entry,
            files: cleanFiles,
            routes: routes,
            name: name is String && name.trim().isNotEmpty ? name.trim() : null,
          );
        }
      }
    }
    final html = AiResponse.extractAppHtml(response);
    if (html.isEmpty) return const AppProject(files: {});
    return AppProject.singleFile(ScriptSanitizer.normalize(html, const {}).html);
  }

  /// `index.html` if present, else the only HTML file.
  static String? _guessEntry(Map<String, String> files) {
    if (files.containsKey('index.html')) return 'index.html';
    final htmls = files.keys.where((k) => k.toLowerCase().endsWith('.html'));
    if (htmls.length == 1) return htmls.first;
    return null;
  }

  /// Normalises a model-provided path, or returns null when it is unsafe.
  static String? safePath(String raw) {
    final p = raw.trim().replaceAll('\\', '/');
    if (p.isEmpty || p.startsWith('/') || p.contains('..')) return null;
    final segments = p.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    for (final s in segments) {
      if (s == '.' || s == '..') return null;
      if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(s)) return null;
    }
    return segments.join('/');
  }

  /// Extensions a text project may contain.
  static const allowedExtensions = {
    'html', 'htm', 'js', 'mjs', 'css', 'json', 'svg', 'txt', 'md', 'webmanifest',
  };

  static const maxFileBytes = 1024 * 1024; // 1 MB per text file
  static const maxTotalBytes = 8 * 1024 * 1024; // 8 MB per project

  /// Null when the project can be built, otherwise a user-facing reason.
  String? validate() {
    if (files.isEmpty) return 'The project has no files.';
    if (!files.containsKey(entry)) return 'The entry file $entry is missing.';
    if (entry != 'index.html') {
      return 'The entry file must be index.html at the project root.';
    }
    var total = 0;
    for (final e in files.entries) {
      if (safePath(e.key) != e.key) return 'Unsafe file name: ${e.key}';
      final dot = e.key.lastIndexOf('.');
      final ext = dot < 0 ? '' : e.key.substring(dot + 1).toLowerCase();
      if (!allowedExtensions.contains(ext)) {
        return 'Unsupported file type: ${e.key}';
      }
      final size = utf8.encode(e.value).length;
      if (size > maxFileBytes) return '${e.key} is larger than 1 MB.';
      total += size;
    }
    if (total > maxTotalBytes) return 'The project is larger than 8 MB.';
    return null;
  }

  /// The `app.json` manifest handed to the app (and to tooling).
  ///
  /// `uiKit` tells the app (and any tooling) where the shared components are:
  /// they are always shipped next to the entry, so multi-file apps can import
  /// them with a relative path.
  String manifestJson() => const JsonEncoder.withIndent('  ').convert({
        'applix': format,
        'entry': entry,
        if (name != null) 'name': name,
        'routes': routes,
        'uiKit': {
          'version': uiKitVersion,
          'css': uiKitCss,
          'js': uiKitJs,
        },
      });

  /// Files packaged into `assets/app/`: the entry, the manifest and modules.
  ///
  /// HTML documents are cleaned with [DevTextSanitizer] so a model summary can
  /// never reach the screen, even in a multi-file project.
  Map<String, String> injectionFiles() {
    final out = <String, String>{};
    for (final e in files.entries) {
      final isHtml = e.key.toLowerCase().endsWith('.html') ||
          e.key.toLowerCase().endsWith('.htm');
      out[e.key] = isHtml ? DevTextSanitizer.removeDevText(e.value) : e.value;
    }
    out['app.json'] = manifestJson();
    return out;
  }

  /// Files other than the entry, ready for the existing build pipeline.
  Map<String, String> extraFiles() {
    final all = injectionFiles()..remove(entry);
    return all;
  }

  // ── JSON discovery ──

  static Map<String, dynamic>? _findProjectJson(String text) {
    // 1) Fenced JSON blocks first - the model was asked to use one.
    final fence =
        RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false);
    for (final m in fence.allMatches(text)) {
      final map = _tryDecode(m.group(1)!);
      if (map != null) return map;
    }
    // 2) Bare object: only braces that can plausibly start a project. Scanning
    // every '{' made a prose/JS-heavy answer quadratic on large responses.
    final limit = text.length > 200000 ? 200000 : text.length;
    final head = text.substring(0, limit);
    final candidate =
        RegExp(r'\{\s*"(?:applix|files|entry|name|routes)"');
    for (final m in candidate.allMatches(head)) {
      final end = _balancedEnd(text, m.start, limit);
      if (end < 0) continue;
      final map = _tryDecode(text.substring(m.start, end));
      if (map != null) return map;
    }
    return null;
  }

  static Map<String, dynamic>? _tryDecode(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    // Strict first: a valid project must never be altered by the repair pass.
    final strict = _decodeProject(text);
    if (strict != null) return strict;

    // Models add smart quotes and trailing commas to otherwise invalid JSON.
    // The repair is string-aware: CSS/JS inside "files" is left byte-for-byte
    // intact, so a valid `1fr,}` in a style string cannot lose its comma.
    final repaired = _repairJson(text);
    final fixed = _decodeProject(repaired);
    if (fixed != null) return fixed;

    // One more attempt after dropping prose inside the fence.
    final first = text.indexOf('{');
    final last = text.lastIndexOf('}');
    if (first >= 0 && last > first) {
      final sliced = text.substring(first, last + 1);
      return _decodeProject(sliced) ?? _decodeProject(_repairJson(sliced));
    }
    return null;
  }

  static Map<String, dynamic>? _decodeProject(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic> && decoded['files'] is Map) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  /// Repairs smart-quoted delimiters and trailing commas outside JSON strings.
  ///
  /// Smart quotes that are part of user-visible copy stay untouched, which is
  /// why this cannot be a global replaceAll.
  static String _repairJson(String text) => JsonRepair.simplify(text);

  /// Index just past the matching `}`, or -1. Quotes and escapes are honoured.
  static int _balancedEnd(String text, int start, int limit) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < limit; i++) {
      final c = text.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == 0x5C) {
          escaped = true;
        } else if (c == 0x22) {
          inString = false;
        }
        continue;
      }
      if (c == 0x22) {
        inString = true;
      } else if (c == 0x7B) {
        depth++;
      } else if (c == 0x7D) {
        depth--;
        if (depth == 0) return i + 1;
      }
    }
    return -1;
  }
}
