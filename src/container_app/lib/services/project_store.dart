// MIT License — Copyright (c) 2026 iappyx

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Stores an app as a small project instead of one big HTML file.
///
/// Layout on the device:
///
///   files/apps/<packageName>/index.html     <- the entry point
///   files/apps/<packageName>/style.css      <- optional extra files
///   files/apps/<packageName>/script.js
///   files/apps/<packageName>/app-config.json
///
/// Before the first build the package name is not known yet, so the project
/// lives in `files/projects/<appId>/` and is moved to `files/apps/<packageName>/`
/// as soon as the app is built.
///
/// Old apps that only have a single index.html (the whole app in one file)
/// keep working: the project folder is optional and the app record always
/// carries the entry HTML.
class ProjectStore {
  /// The project description stored next to the files.
  static const configFile = 'app-config.json';

  /// Overrides the storage root (tests only).
  @visibleForTesting
  static String? rootOverride;

  /// The folder that holds files/apps/ and files/projects/.
  static Future<String> _root() async {
    if (rootOverride != null) return rootOverride!;
    return (await getApplicationSupportDirectory()).path;
  }

  /// Where the project of an app lives.
  static Future<Directory> projectDir({
    required String appId,
    String? packageName,
  }) async {
    final root = await _root();
    final name = (packageName != null && packageName.isNotEmpty)
        ? 'apps/$packageName'
        : 'projects/$appId';
    final dir = Directory('$root/$name');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Writes the entry HTML and the extra project files.
  static Future<void> writeProject({
    required String appId,
    String? packageName,
    required String indexHtml,
    Map<String, String> files = const {},
  }) async {
    final dir = await projectDir(appId: appId, packageName: packageName);
    File('${dir.path}/index.html').writeAsStringSync(indexHtml);
    for (final entry in files.entries) {
      final name = _safeRelativePath(entry.key);
      if (name == null || name == 'index.html') continue;
      final f = File('${dir.path}/$name');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(entry.value);
    }
  }

  /// Adds or replaces a single project file.
  static Future<void> addFile({
    required String appId,
    String? packageName,
    required String name,
    required String content,
  }) async {
    final dir = await projectDir(appId: appId, packageName: packageName);
    final safe = _safeRelativePath(name);
    if (safe == null || safe == 'index.html') return;
    final f = File('${dir.path}/$safe');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  static Future<void> removeFile({
    required String appId,
    String? packageName,
    required String name,
  }) async {
    final dir = await projectDir(appId: appId, packageName: packageName);
    final safe = _safeRelativePath(name);
    if (safe == null || safe == 'index.html') return;
    final f = File('${dir.path}/$safe');
    if (f.existsSync()) f.deleteSync();
  }

  /// All project files (name -> content). Binary files are skipped.
  static Future<Map<String, String>> readProject({
    required String appId,
    String? packageName,
  }) async {
    final dir = await projectDir(appId: appId, packageName: packageName);
    if (!dir.existsSync()) return {};
    final map = <String, String>{};
    for (final f in _filesRecursive(dir)) {
      final name = _relativeName(dir, f);
      if (name == configFile) continue;
      try {
        map[name] = f.readAsStringSync();
      } catch (_) {
        // Binary file - not a text project file.
      }
    }
    return map;
  }

  /// The entry HTML of the project (null when the app has no project folder).
  static Future<String?> readIndexHtml({
    required String appId,
    String? packageName,
  }) async {
    final dir = await projectDir(appId: appId, packageName: packageName);
    final f = File('${dir.path}/index.html');
    if (!f.existsSync()) return null;
    try {
      return f.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  /// The project files as {name: absolute path} for the build.
  static Future<Map<String, String>> paths({
    required String appId,
    String? packageName,
  }) async {
    final dir = await projectDir(appId: appId, packageName: packageName);
    if (!dir.existsSync()) return {};
    final map = <String, String>{};
    for (final f in _filesRecursive(dir)) {
      final name = _relativeName(dir, f);
      if (name == 'index.html' || name == configFile) continue;
      map[name] = f.path;
    }
    return map;
  }

  /// The list of project files for the UI.
  static Future<List<Map<String, dynamic>>> listFiles({
    required String appId,
    String? packageName,
  }) async {
    final dir = await projectDir(appId: appId, packageName: packageName);
    if (!dir.existsSync()) return [];
    final entries = <Map<String, dynamic>>[];
    for (final f in _filesRecursive(dir)) {
      final name = _relativeName(dir, f);
      if (name == configFile) continue;
      entries.add({'name': name, 'size': f.lengthSync(), 'path': f.path});
    }
    entries.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return entries;
  }

  /// Removes the whole project folder.
  static Future<void> deleteProject({
    required String appId,
    String? packageName,
  }) async {
    final root = await _root();
    final dirs = <String>[
      if (packageName != null && packageName.isNotEmpty) 'apps/$packageName',
      'projects/$appId',
    ];
    for (final d in dirs) {
      final dir = Directory('$root/$d');
      if (dir.existsSync()) {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// Moves the project to its final place once the package name is known.
  static Future<void> migrateToPackage({
    required String appId,
    required String packageName,
  }) async {
    if (packageName.isEmpty) return;
    final root = await _root();
    final from = Directory('$root/projects/$appId');
    final to = Directory('$root/apps/$packageName');
    if (!from.existsSync()) return;
    try {
      if (!to.existsSync()) to.createSync(recursive: true);
      for (final f in _filesRecursive(from)) {
        final rel = _relativeName(from, f);
        final dest = File('${to.path}/$rel');
        dest.parent.createSync(recursive: true);
        if (dest.existsSync()) dest.deleteSync();
        f.copySync(dest.path);
      }
      from.deleteSync(recursive: true);
    } catch (_) {
      // The build must not fail because of a folder move.
    }
  }

  /// Writes the small project manifest (name, version, entry file).
  static Future<void> writeConfig({
    required String appId,
    String? packageName,
    required Map<String, dynamic> config,
  }) async {
    final dir = await projectDir(appId: appId, packageName: packageName);
    File('${dir.path}/$configFile')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(config));
  }

  /// Reads the project manifest (null when there is none).
  static Future<Map<String, dynamic>?> readConfig({
    required String appId,
    String? packageName,
  }) async {
    final dir = await projectDir(appId: appId, packageName: packageName);
    final f = File('${dir.path}/$configFile');
    if (!f.existsSync()) return null;
    try {
      final decoded = jsonDecode(f.readAsStringSync());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Inlines the project files into the HTML.
  ///
  /// The preview loads the app as a string, so <link href="style.css"> and
  /// <script src="script.js"> cannot be resolved there. Inlining them makes
  /// the preview show exactly what the installed app shows.
  static String inlineProjectFiles(String html, Map<String, String> files) {
    if (files.isEmpty) return html;
    final cache = <String, String>{};
    var out = html;

    // <link rel="stylesheet" href="./style.css?v=2"> -> <style>...</style>
    out = out.replaceAllMapped(
      RegExp(r'<link\b[^>]*>', caseSensitive: false),
      (m) {
        final tag = m.group(0)!;
        final rel = _attr(tag, 'rel');
        final href = _attr(tag, 'href');
        if (rel == null ||
            !RegExp(r'(^|\s)stylesheet(\s|$)', caseSensitive: false)
                .hasMatch(rel) ||
            href == null) {
          return tag;
        }
        final key = _resolveFileRef(href, 'index.html', files);
        if (key == null) return tag;
        return '<style data-applix-file="$key">\n'
            '${_escapeStyle(files[key]!)}\n</style>';
      },
    );

    // <script src="./app.js"></script> -> inline script. Module imports are
    // rewritten recursively to data: URLs so they resolve without the APK's
    // real origin.
    out = out.replaceAllMapped(
      RegExp(r'<script\b([^>]*)>\s*</script>',
          caseSensitive: false, dotAll: true),
      (m) {
        final attrs = m.group(1) ?? '';
        final src = _attr(attrs, 'src');
        if (src == null) return m.group(0)!;
        final key = _resolveFileRef(src, 'index.html', files);
        if (key == null) return m.group(0)!;
        final isModule = RegExp(
                r'''type\s*=\s*(?:"module"|'module')''',
                caseSensitive: false)
            .hasMatch(attrs);
        var code = files[key]!;
        if (isModule) {
          code = _rewriteModuleSpecifiers(
              code, key, files, cache, <String>{});
        }
        final cleanAttrs = attrs.replaceAll(
          RegExp(r'''\s+src\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)''',
              caseSensitive: false),
          '',
        );
        return '<script$cleanAttrs>\n${_escapeScript(code)}\n</script>';
      },
    );

    // Inline module blocks already in index.html also need their relative
    // imports rewritten (e.g. `import { toast } from './applix-ui.js'`).
    out = out.replaceAllMapped(
      RegExp(
          r'''<script\b([^>]*type\s*=\s*(["'])module\2[^>]*)>([\s\S]*?)</script>''',
          caseSensitive: false),
      (m) {
        final attrs = m.group(1) ?? '';
        final code = _rewriteModuleSpecifiers(
            m.group(3) ?? '', 'index.html', files, cache, <String>{});
        return '<script$attrs>\n${_escapeScript(code)}\n</script>';
      },
    );
    return out;
  }

  static String? _attr(String tag, String name) {
    final re = RegExp(
      '(?:^|\\s)${RegExp.escape(name)}\\s*=\\s*'
      '(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
      caseSensitive: false,
    );
    final m = re.firstMatch(tag);
    if (m == null) return null;
    return m.group(1) ?? m.group(2) ?? m.group(3);
  }

  static bool _isRelativeSpecifier(String spec) {
    return spec.startsWith('./') ||
        spec.startsWith('../') ||
        spec.startsWith('/');
  }

  static String? _resolveFileRef(
      String ref, String fromKey, Map<String, String> files) {
    var path = ref.trim();
    if (path.isEmpty) return null;
    final lower = path.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('data:') ||
        lower.startsWith('blob:') ||
        lower.startsWith('//') ||
        lower.startsWith('#')) {
      return null;
    }
    path = path.split('#').first.split('?').first;
    if (path.isEmpty) return null;
    if (!path.startsWith('/')) {
      final slash = fromKey.lastIndexOf('/');
      final dir = slash >= 0 ? fromKey.substring(0, slash) : '';
      path = dir.isEmpty ? path : '$dir/$path';
    }
    path = _normalizeRelative(path);
    return files.containsKey(path) ? path : null;
  }

  static String _normalizeRelative(String path) {
    final out = <String>[];
    for (final segment in path.replaceAll('\\', '/').split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (out.isNotEmpty) out.removeLast();
        continue;
      }
      out.add(segment);
    }
    return out.join('/');
  }

  static String _rewriteModuleSpecifiers(
    String code,
    String fromKey,
    Map<String, String> files,
    Map<String, String> cache,
    Set<String> stack,
  ) {
    var out = code.replaceAllMapped(
      RegExp(r'''((?:\bfrom\s*|\bimport\s*)(["']))([^"']+)(\2)'''),
      (m) {
        final spec = m.group(3)!;
        if (!_isRelativeSpecifier(spec)) return m.group(0)!;
        final key = _resolveFileRef(spec, fromKey, files);
        if (key == null) return m.group(0)!;
        final url = _moduleDataUrl(key, files, cache, stack);
        return '${m.group(1)}"$url"';
      },
    );
    out = out.replaceAllMapped(
      RegExp(r'''(\bimport\s*\(\s*)(["'])([^"']+)(\2)(\s*\))'''),
      (m) {
        final spec = m.group(3)!;
        if (!_isRelativeSpecifier(spec)) return m.group(0)!;
        final key = _resolveFileRef(spec, fromKey, files);
        if (key == null) return m.group(0)!;
        final url = _moduleDataUrl(key, files, cache, stack);
        return '${m.group(1)}"$url"${m.group(5)}';
      },
    );
    return out;
  }

  static String _moduleDataUrl(
    String key,
    Map<String, String> files,
    Map<String, String> cache,
    Set<String> stack,
  ) {
    final cached = cache[key];
    if (cached != null) return cached;
    final content = files[key] ?? '';
    // Cycles cannot be represented as nested data: URLs without infinite
    // recursion. Leave the raw module in that rare case.
    if (stack.contains(key)) {
      return 'data:text/javascript;base64,'
          '${base64Encode(utf8.encode(content))}';
    }
    stack.add(key);
    final rewritten =
        _rewriteModuleSpecifiers(content, key, files, cache, stack);
    stack.remove(key);
    final url =
        'data:text/javascript;base64,${base64Encode(utf8.encode(rewritten))}';
    cache[key] = url;
    return url;
  }

  static String _escapeScript(String code) => code.replaceAll(
      RegExp(r'</script', caseSensitive: false), r'<\/script');

  static String _escapeStyle(String css) => css.replaceAll(
      RegExp(r'</style', caseSensitive: false), r'<\/style');

  /// Project file paths (flat or nested like `src/app.js`) must stay inside
  /// the project folder. Each segment is sanitised; traversal is rejected.
  static String? _safeRelativePath(String name) {
    final p = name.trim().replaceAll('\\', '/');
    if (p.isEmpty || p.startsWith('/') || p.contains('..')) return null;
    final segments = p.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    final clean = <String>[];
    for (final s in segments) {
      if (s == '.' || s == '..') return null;
      final safe = s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      if (safe.isEmpty) return null;
      clean.add(safe);
    }
    return clean.join('/');
  }

  /// Every file below [dir], recursively, sorted for stable output.
  static List<File> _filesRecursive(Directory dir) {
    final files = <File>[];
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is File && !entity.path.contains('/.') && entity.uri.pathSegments.last != '.DS_Store') {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  /// Path of [file] relative to [dir], with forward slashes.
  static String _relativeName(Directory dir, File file) {
    final base = dir.path.endsWith('/') ? dir.path : '${dir.path}/';
    final path = file.path;
    return path.startsWith(base) ? path.substring(base.length) : file.uri.pathSegments.last;
  }
}
