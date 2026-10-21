// MIT License
//
// Copyright (c) 2026 iappyx
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

/// Targeted updates for an existing app.
///
/// A follow-up used to replace the complete app, which is slow and can silently
/// lose working code. A patch changes only the lines that need to change. The
/// model is asked for an [AppPatch] JSON; if the patch is unsafe (a `find`
/// string is missing or ambiguous) nothing is applied and the caller lets the
/// user retry, instead of guessing.
library;

import 'dart:convert';

import 'app_project.dart';

class PatchOutcome {
  final AppProject? project;
  final String? error;

  const PatchOutcome.applied(this.project) : error = null;
  const PatchOutcome.failed(this.error) : project = null;

  bool get ok => project != null;
}

class AppPatch {
  static const int format = 1;
  static const int maxEdits = 24;
  static const int maxFindChars = 20000;
  static const int maxContentChars = 400000;

  /// Appended to a follow-up user message. The full schema lives in the
  /// system prompt, so this only switches the model into update mode.
  static const String instruction = '''

PATCH MODE: This app already exists. Change it, do not recreate it.
Return ONLY one JSON object:
{"applix_patch":1,"edits":[{"op":"replace","find":"exact current code","replace":"new code"}],"files":{}}
Use "insert_after" with "content" to add code, "delete" to remove code. Every
"find" must be an exact substring of the current code and must occur once.
"files" is optional and only replaces whole files. Do not rewrite unchanged code.
If a safe patch is impossible, return the complete app as usual.''';

  final List<Map<String, dynamic>> edits;
  final Map<String, String> files;

  const AppPatch({this.edits = const [], this.files = const {}});

  /// Parses a model answer. Returns null when the answer is not a patch.
  /// Throws [FormatException] when it claims to be a patch but is malformed.
  static AppPatch? parse(String response) {
    final map = _findObject(response);
    if (map == null) return null;
    if (map['applix_patch'] != format) {
      if (map.containsKey('applix_patch')) {
        throw const FormatException('Unsupported patch version.');
      }
      return null;
    }

    final rawEdits = map['edits'];
    final edits = <Map<String, dynamic>>[];
    if (rawEdits != null) {
      if (rawEdits is! List) throw const FormatException('edits must be a list.');
      if (rawEdits.length > maxEdits) {
        throw const FormatException('Too many edits in one patch.');
      }
      for (final raw in rawEdits) {
        if (raw is! Map) throw const FormatException('An edit is not an object.');
        edits.add(Map<String, dynamic>.from(raw));
      }
    }

    final files = <String, String>{};
    final rawFiles = map['files'];
    if (rawFiles is Map) {
      rawFiles.forEach((key, value) {
        if (key is! String || value is! String) {
          throw const FormatException('Patch files must be strings.');
        }
        final path = AppProject.safePath(key);
        if (path == null || value.trim().isEmpty) {
          throw FormatException('Unsafe patch file: $key');
        }
        files[path] = value;
      });
    }

    if (edits.isEmpty && files.isEmpty) {
      throw const FormatException('The patch has no changes.');
    }
    return AppPatch(edits: edits, files: files);
  }

  /// Applies a patch response to a complete project. Returns null when the
  /// response is not a patch. A claimed patch that cannot be applied returns
  /// [PatchOutcome.failed] so the caller never silently keeps a broken update.
  static PatchOutcome? applyToProject(String response, AppProject current) {
    AppPatch? patch;
    try {
      patch = parse(response);
    } on FormatException catch (e) {
      return PatchOutcome.failed(e.message);
    }
    if (patch == null) return null;

    final files = Map<String, String>.from(current.files);
    files.addAll(patch.files);
    final entry = current.entry;
    final edited = _applyEdits(patch.edits, files[entry] ?? '');
    if (edited.error != null) return PatchOutcome.failed(edited.error);
    files[entry] = edited.html!;

    final project = AppProject(
      entry: entry,
      files: files,
      routes: current.routes,
      name: current.name,
    );
    final invalid = project.validate();
    if (invalid != null) return PatchOutcome.failed(invalid);
    return PatchOutcome.applied(project);
  }

  /// Applies a patch response to a single HTML string. Null when it is not a
  /// patch; a failed outcome when the patch cannot be applied.
  static PatchOutcome? applyToHtml(String response, String html) {
    AppPatch? patch;
    try {
      patch = parse(response);
    } on FormatException catch (e) {
      return PatchOutcome.failed(e.message);
    }
    if (patch == null) return null;
    if (patch.files.isNotEmpty) {
      return const PatchOutcome.failed('This update changes project files.');
    }
    final edited = _applyEdits(patch.edits, html);
    if (edited.error != null) return PatchOutcome.failed(edited.error);
    final project = AppProject.singleFile(edited.html!);
    final invalid = project.validate();
    if (invalid != null) return PatchOutcome.failed(invalid);
    return PatchOutcome.applied(project);
  }

  static _EditResult _applyEdits(List<Map<String, dynamic>> edits, String source) {
    var out = source;
    for (final edit in edits) {
      final op = (edit['op'] as String?)?.trim().toLowerCase();
      final find = edit['find'];
      if (op == null || find is! String || find.isEmpty) {
        return const _EditResult.error('An edit is missing op or find.');
      }
      if (find.length > maxFindChars) {
        return const _EditResult.error('A find string is too long.');
      }
      final first = out.indexOf(find);
      if (first < 0) {
        return const _EditResult.error('The code to change was not found.');
      }
      if (out.indexOf(find, first + 1) >= 0) {
        return const _EditResult.error('The code to change is not unique.');
      }

      switch (op) {
        case 'replace':
          final replacement = edit['replace'];
          if (replacement is! String) {
            return const _EditResult.error('replace must be a string.');
          }
          if (replacement.length > maxContentChars) {
            return const _EditResult.error('The replacement is too long.');
          }
          out = out.replaceRange(first, first + find.length, replacement);
          break;
        case 'insert_after':
          final content = edit['content'];
          if (content is! String) {
            return const _EditResult.error('content must be a string.');
          }
          if (content.length > maxContentChars) {
            return const _EditResult.error('The inserted code is too long.');
          }
          out = out.replaceRange(first + find.length, first + find.length, content);
          break;
        case 'delete':
          out = out.replaceRange(first, first + find.length, '');
          break;
        default:
          return _EditResult.error('Unsupported edit op: $op');
      }
    }
    if (out.trim().isEmpty || !out.trimLeft().startsWith('<')) {
      return const _EditResult.error('The patch produced invalid HTML.');
    }
    return _EditResult.html(out);
  }

  static Map<String, dynamic>? _findObject(String text) {
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false);
    for (final m in fence.allMatches(text)) {
      final map = _tryDecode(m.group(1)!);
      if (map != null) return map;
    }
    final marker = text.indexOf('"applix_patch"');
    if (marker < 0) return null;
    for (var i = marker; i >= 0; i--) {
      if (text[i] != '{') continue;
      final end = _balancedEnd(text, i);
      if (end < 0) continue;
      final map = _tryDecode(text.substring(i, end));
      if (map != null) return map;
    }
    return _tryDecode(text);
  }

  static Map<String, dynamic>? _tryDecode(String raw) {
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is Map<String, dynamic> && decoded.containsKey('applix_patch')) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  static int _balancedEnd(String text, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) return i + 1;
      }
    }
    return -1;
  }
}

class _EditResult {
  final String? html;
  final String? error;

  const _EditResult.html(this.html) : error = null;
  const _EditResult.error(this.error) : html = null;
}
