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

/// Runtime verification for generated apps.
///
/// The static auditor cannot see whether the app actually boots. [RuntimeProbe]
/// is injected into the preview WebView, records uncaught errors, and reports
/// whether the app rendered anything. A fatal report blocks the build instead
/// of shipping a white screen.
library;

import 'dart:convert';

class RuntimeReport {
  final bool ready;
  final bool loaded;
  final int textLength;
  final int interactive;
  final int bodyChildren;
  final int visuals;
  final List<String> errors;
  final String? inconclusiveReason;

  const RuntimeReport({
    required this.ready,
    required this.loaded,
    required this.textLength,
    required this.interactive,
    required this.bodyChildren,
    required this.visuals,
    required this.errors,
    this.inconclusiveReason,
  });

  factory RuntimeReport.fromJson(Map<String, dynamic> json) {
    final errors = <String>[];
    final raw = json['errors'];
    if (raw is List) {
      for (final e in raw) {
        if (e is String && e.trim().isNotEmpty) errors.add(e.trim());
      }
    }
    int asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
    return RuntimeReport(
      ready: json['ready'] == true,
      loaded: json['loaded'] == true,
      textLength: asInt(json['textLength']),
      interactive: asInt(json['interactive']),
      bodyChildren: asInt(json['bodyChildren']),
      visuals: asInt(json['visuals']),
      errors: errors,
    );
  }

  factory RuntimeReport.inconclusive(String reason) => RuntimeReport(
        ready: false,
        loaded: false,
        textLength: 0,
        interactive: 0,
        bodyChildren: 0,
        visuals: 0,
        errors: const [],
        inconclusiveReason: reason,
      );

  static RuntimeReport? parse(Object? raw) {
    var text = raw is String ? raw : raw?.toString() ?? '';
    try {
      if (text.startsWith('"')) text = jsonDecode(text) as String;
    } catch (_) {}
    if (text.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return RuntimeReport.fromJson(decoded);
    } catch (_) {}
    return null;
  }

  /// Errors that mean the app will not work for the user.
  List<String> get fatalErrors => errors.where((e) => !_isBenign(e) && !_isPreviewLimitation(e)).toList();

  /// Preview-only failures: ES module files are inlined into the preview, so
  /// relative imports cannot resolve there even though the installed app can
  /// load them from its real origin.
  List<String> get previewLimitations =>
      errors.where(_isPreviewLimitation).toList();

  bool get blank => ready &&
      bodyChildren == 0 &&
      textLength < 2 &&
      interactive == 0 &&
      visuals == 0;

  bool get fatal => fatalErrors.isNotEmpty || blank;

  bool get passed => !fatal && inconclusiveReason == null;

  String get summary {
    if (inconclusiveReason != null) return 'Runtime check skipped: $inconclusiveReason';
    if (fatal) {
      if (blank) return 'The app rendered a blank screen.';
      return fatalErrors.first;
    }
    if (previewLimitations.isNotEmpty) {
      return 'No app errors found (module imports are validated after install).';
    }
    if (errors.isNotEmpty) return 'The app started with ${errors.length} warning(s).';
    return 'The app started without JavaScript errors.';
  }

  static bool _isBenign(String error) {
    final e = error.toLowerCase();
    return e.contains('resizeobserver loop') ||
        e.contains('favicon') ||
        e.contains('net::err_file_not_found') ||
        e.contains('abortError'.toLowerCase());
  }

  static bool _isPreviewLimitation(String error) {
    final e = error.toLowerCase();
    return e.contains('failed to resolve module specifier') ||
        e.contains('importing a module script failed') ||
        e.contains('cannot use import statement outside a module') ||
        e.contains('failed to fetch dynamically imported module');
  }
}

class RuntimeProbe {
  static const String channelName = 'ApplixRuntime';

  /// Runs after the bridge shim but before app code. It must never throw: a
  /// probe bug would otherwise become an app error.
  static const String bootstrap = '''
<script>
(function () {
  try {
    var r = window.__applixRuntime = {
      errors: [], ready: false, loaded: false, domReady: false,
      textLength: 0, interactive: 0, bodyChildren: 0, visuals: 0
    };
    var seen = {};
    function push(msg, source) {
      try {
        var text = String(msg || 'Unknown error');
        if (source) text += ' (' + source + ')';
        if (text.length > 300) text = text.substring(0, 300) + '…';
        if (seen[text]) return;
        seen[text] = true;
        if (r.errors.length < 10) r.errors.push(text);
      } catch (_) {}
    }
    window.addEventListener('error', function (e) {
      try {
        if (e && e.target && e.target !== window && e.target.tagName) {
          var tag = String(e.target.tagName).toLowerCase();
          if (tag === 'img' || tag === 'link' || tag === 'source') return;
        }
        var where = e && e.lineno ? ' @' + e.lineno + ':' + (e.colno || 0) : '';
        push((e && e.message ? e.message : 'Script error') + where, e && e.filename);
      } catch (_) {}
    }, true);
    window.addEventListener('unhandledrejection', function (e) {
      try {
        var reason = e && e.reason;
        push('Unhandled rejection: ' + (reason && reason.message ? reason.message : reason));
      } catch (_) {}
    });
    var originalError = console.error;
    console.error = function () {
      try {
        push(Array.prototype.map.call(arguments, function (a) {
          return a && a.message ? a.message : String(a);
        }).join(' '), 'console.error');
      } catch (_) {}
      return originalError.apply(console, arguments);
    };
    document.addEventListener('DOMContentLoaded', function () { r.domReady = true; });
    window.addEventListener('load', function () { r.loaded = true; });
    setTimeout(function () {
      try {
        var body = document.body;
        r.textLength = body ? ((body.innerText || body.textContent || '').trim().length) : 0;
        r.interactive = document.querySelectorAll('button, a, input, select, textarea, [role="button"], [onclick]').length;
        r.bodyChildren = body ? body.children.length : 0;
        r.visuals = document.querySelectorAll('canvas, svg, video, img').length;
        r.ready = true;
      } catch (e) {
        push('Runtime probe failed: ' + (e && e.message ? e.message : e));
        r.ready = true;
      }
    }, 1400);
  } catch (_) {}
})();
</script>
''';

  /// Injects the probe before app code, right after `<head>` when possible.
  static String inject(String html) {
    final headIdx = html.toLowerCase().indexOf('<head');
    if (headIdx != -1) {
      final closeIdx = html.indexOf('>', headIdx);
      if (closeIdx != -1) {
        return html.substring(0, closeIdx + 1) + bootstrap + html.substring(closeIdx + 1);
      }
    }
    return bootstrap + html;
  }
}
