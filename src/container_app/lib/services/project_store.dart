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
    var out = html;
    files.forEach((name, content) {
      final escaped = RegExp.escape(name);
      // <link rel="stylesheet" href="style.css"> -> <style>...</style>
      out = out.replaceAllMapped(
        RegExp('<link[^>]*href=["\']$escaped["\'][^>]*>', caseSensitive: false),
        (m) => '<style>\n$content\n</style>',
      );
      // <script src="script.js"></script> -> <script>...</script>.
      // type="module" is preserved (module semantics stay intact; relative
      // imports inside the module still need the built app's real origin).
      out = out.replaceAllMapped(
        RegExp('<script([^>]*)src=["\']$escaped["\']([^>]*)>\s*</script>', caseSensitive: false),
        (m) {
          final attrs = '${m.group(1) ?? ''}${m.group(2) ?? ''}';
          final isModule = attrs.toLowerCase().contains('type="module"') ||
              attrs.toLowerCase().contains("type='module'");
          return isModule
              ? '<script type="module">\n$content\n</script>'
              : '<script>\n$content\n</script>';
        },
      );
    });
    return out;
  }

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
