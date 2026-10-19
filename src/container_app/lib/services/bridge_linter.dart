import 'dart:convert';

import 'package:flutter/services.dart';

enum BridgeIssueKind { unknownModule, unknownMethod, unknownTopLevel }

class BridgeIssue {
  final BridgeIssueKind kind;
  final String module;
  final String method;
  final int line;
  final String snippet;

  const BridgeIssue({
    required this.kind,
    required this.module,
    required this.method,
    required this.line,
    required this.snippet,
  });

  String get call {
    if (module.isEmpty) return 'iappyx.$method';
    if (method.isEmpty) return 'iappyx.$module';
    return 'iappyx.$module.$method';
  }

  String get message {
    switch (kind) {
      case BridgeIssueKind.unknownModule:
        return 'unknown bridge module "$module"';
      case BridgeIssueKind.unknownMethod:
        return 'unknown bridge method "$module.$method"';
      case BridgeIssueKind.unknownTopLevel:
        return 'unknown top-level bridge method "$method"';
    }
  }

  String get consoleLine => '[Bridge] line $line: $message ($call)';
}

class BridgeIndex {
  final Map<String, Set<String>> modules;
  final Set<String> topLevel;

  const BridgeIndex(this.modules, this.topLevel);

  factory BridgeIndex.fromJson(Map<String, dynamic> json) {
    final modules = <String, Set<String>>{};
    final rawModules = json['modules'];
    if (rawModules is Map) {
      rawModules.forEach((key, value) {
        if (value is List) {
          modules[key.toString()] = value.map((item) => item.toString()).toSet();
        }
      });
    }
    final rawTopLevel = json['topLevel'];
    final topLevel = rawTopLevel is List
        ? rawTopLevel.map((item) => item.toString()).toSet()
        : <String>{};
    return BridgeIndex(modules, topLevel);
  }
}

/// Static validation of direct `iappyx.*` / `applix.*` calls against SPEC.md.
///
/// Known limitations (by design, to stay dependency-free):
/// - dynamic access (`iappyx[m][x]`) is skipped
/// - aliases (`var a = iappyx.audio; a.play()`) are not resolved
/// - code inside template-literal `${...}` is skipped
class BridgeLinter {
  final BridgeIndex index;

  const BridgeLinter(this.index);

  static BridgeLinter? _cached;

  static Future<BridgeLinter> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/bridge_index.json');
    final linter = BridgeLinter(
      BridgeIndex.fromJson(jsonDecode(raw) as Map<String, dynamic>),
    );
    _cached = linter;
    return linter;
  }

  static final _scriptBlock =
      RegExp(r'<script\b[^>]*>([\s\S]*?)</script>', caseSensitive: false);
  static final _reference = RegExp(
    r'(?:window\s*\.\s*|self\s*\.\s*)?(?:iappyx|applix)\s*\.\s*([A-Za-z_$][\w$]*)',
  );
  static final _identifier = RegExp(r'[A-Za-z_$][\w$]*');

  List<BridgeIssue> lint(String html) {
    final found = <String, BridgeIssue>{};
    final htmlLines = html.split('\n');

    for (final script in _scriptBlock.allMatches(html)) {
      final content = script.group(1) ?? '';
      if (content.trim().isEmpty) continue;
      final baseLine = _lineNumber(html, script.start);
      final sanitized = _sanitize(content);

      for (final ref in _reference.allMatches(sanitized)) {
        if (ref.start > 0) {
          final previous = sanitized.codeUnitAt(ref.start - 1);
          if (_isIdentifierChar(previous) || previous == 0x2E || previous == 0x24) {
            continue;
          }
        }

        final name = ref.group(1)!;
        var pos = ref.end;
        while (pos < sanitized.length && _isSpace(sanitized.codeUnitAt(pos))) {
          pos++;
        }

        if (pos < sanitized.length && sanitized[pos] == '[') {
          continue; // dynamic access
        }

        String? method;
        if (pos < sanitized.length && sanitized[pos] == '.') {
          pos++;
          while (pos < sanitized.length && _isSpace(sanitized.codeUnitAt(pos))) {
            pos++;
          }
          final match = _identifier.matchAsPrefix(sanitized, pos);
          if (match == null) continue;
          method = match.group(0);
        } else if (pos >= sanitized.length || sanitized[pos] != '(') {
          // Bare reference (module object or top-level function reference).
          if (index.modules.containsKey(name) || index.topLevel.contains(name)) {
            continue;
          }
          _addIssue(
            found,
            kind: BridgeIssueKind.unknownModule,
            module: name,
            method: '',
            refStart: ref.start,
            baseLine: baseLine,
            content: content,
            htmlLines: htmlLines,
          );
          continue;
        }

        if (method == null) {
          if (!index.topLevel.contains(name)) {
            _addIssue(
              found,
              kind: BridgeIssueKind.unknownTopLevel,
              module: '',
              method: name,
              refStart: ref.start,
              baseLine: baseLine,
              content: content,
              htmlLines: htmlLines,
            );
          }
          continue;
        }

        final methods = index.modules[name];
        if (methods == null) {
          _addIssue(
            found,
            kind: BridgeIssueKind.unknownModule,
            module: name,
            method: method,
            refStart: ref.start,
            baseLine: baseLine,
            content: content,
            htmlLines: htmlLines,
          );
        } else if (!methods.contains(method)) {
          _addIssue(
            found,
            kind: BridgeIssueKind.unknownMethod,
            module: name,
            method: method,
            refStart: ref.start,
            baseLine: baseLine,
            content: content,
            htmlLines: htmlLines,
          );
        }
      }
    }

    final issues = found.values.toList()..sort((a, b) => a.line.compareTo(b.line));
    return issues;
  }

  void _addIssue(
    Map<String, BridgeIssue> found, {
    required BridgeIssueKind kind,
    required String module,
    required String method,
    required int refStart,
    required int baseLine,
    required String content,
    required List<String> htmlLines,
  }) {
    final key = '$module.$method';
    if (found.containsKey(key)) return;
    final line = baseLine + _newlinesBefore(content, refStart);
    final snippet = line > 0 && line <= htmlLines.length
        ? htmlLines[line - 1].trim()
        : '';
    found[key] = BridgeIssue(
      kind: kind,
      module: module,
      method: method,
      line: line,
      snippet: snippet.length > 120 ? '${snippet.substring(0, 120)}…' : snippet,
    );
  }

  static int _lineNumber(String text, int offset) {
    var line = 1;
    for (var i = 0; i < offset && i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) line++;
    }
    return line;
  }

  static int _newlinesBefore(String text, int offset) {
    var count = 0;
    for (var i = 0; i < offset && i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) count++;
    }
    return count;
  }

  static bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

  static bool _isIdentifierChar(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      c == 0x24;

  /// Replaces comments and string/template bodies with spaces while keeping
  /// offsets and newlines intact, so line numbers stay correct.
  static String _sanitize(String source) {
    final out = StringBuffer();
    var state = _LexState.code;
    var i = 0;
    while (i < source.length) {
      final c = source[i];
      final next = i + 1 < source.length ? source[i + 1] : '';
      if (state == _LexState.lineComment) {
        if (c == '\n') {
          out.write('\n');
          state = _LexState.code;
        } else {
          out.write(' ');
        }
        i++;
        continue;
      }
      if (state == _LexState.blockComment) {
        if (c == '*' && next == '/') {
          out.write('  ');
          i += 2;
          state = _LexState.code;
        } else {
          out.write(c == '\n' ? '\n' : ' ');
          i++;
        }
        continue;
      }
      if (state != _LexState.code) {
        final quote = state == _LexState.single
            ? "'"
            : state == _LexState.double
                ? '"'
                : '`';
        if (c == '\\' && i + 1 < source.length) {
          out.write(next == '\n' ? '\n' : ' ');
          i += 2;
          continue;
        }
        if (c == quote) {
          out.write(' ');
          i++;
          state = _LexState.code;
          continue;
        }
        out.write(c == '\n' ? '\n' : ' ');
        i++;
        continue;
      }
      if (c == '/' && next == '/') {
        out.write('  ');
        i += 2;
        state = _LexState.lineComment;
        continue;
      }
      if (c == '/' && next == '*') {
        out.write('  ');
        i += 2;
        state = _LexState.blockComment;
        continue;
      }
      if (c == "'") {
        out.write(' ');
        i++;
        state = _LexState.single;
        continue;
      }
      if (c == '"') {
        out.write(' ');
        i++;
        state = _LexState.double;
        continue;
      }
      if (c == '`') {
        out.write(' ');
        i++;
        state = _LexState.template;
        continue;
      }
      out.write(c);
      i++;
    }
    return out.toString();
  }

  static String buildRepairMessage(List<BridgeIssue> issues) {
    final buffer = StringBuffer()
      ..writeln(
        'Static bridge validation found ${issues.length} invalid bridge call(s) '
        'in the HTML you just returned:',
      );
    for (final issue in issues) {
      buffer.writeln('- line ${issue.line}: ${issue.call} — ${issue.message}');
    }
    buffer
      ..writeln()
      ..writeln(
        'Fix ONLY these calls using methods documented in the Bridge reference. '
        'If an invalid capability is not documented, remove that feature. '
        'Keep the rest of the app unchanged. Return the complete corrected HTML file only.',
      );
    return buffer.toString();
  }

  static String formatIssues(List<BridgeIssue> issues) =>
      issues.map((issue) => issue.consoleLine).join('\n');
}

enum _LexState { code, single, double, template, lineComment, blockComment }
