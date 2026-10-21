/// Applix UI Kit - injects the built-in design system into generated apps.
///
/// The stylesheet is added as the FIRST <style> block, so an app's own CSS
/// always wins. Apps can opt out with:
///   <meta name="applix-ui" content="off">
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class UiKit {
  static const assetPath = 'assets/applix-ui.css';
  static const jsAssetPath = 'assets/applix-ui.js';
  static const styleId = 'applix-ui-kit';

  /// Names of the kit files shipped next to index.html in every built app.
  static const cssFileName = 'applix-ui.css';
  static const jsFileName = 'applix-ui.js';

  /// Version advertised in app.json (`uiKit.version`).
  static const version = 2;

  static String? _css;
  static String? _js;

  /// The design system CSS (cached after the first read).
  static Future<String> loadCss() async {
    if (_css != null) return _css!;
    try {
      _css = await rootBundle.loadString(assetPath);
    } catch (_) {
      _css = '';
    }
    return _css!;
  }

  /// The companion ES module (cached after the first read).
  static Future<String> loadJs() async {
    if (_js != null) return _js!;
    try {
      _js = await rootBundle.loadString(jsAssetPath);
    } catch (_) {
      _js = '';
    }
    return _js!;
  }

  /// True when the app explicitly opted out of the UI kit.
  static bool isOptedOut(String html) {
    final lower = html.toLowerCase();
    if (!lower.contains('applix-ui')) return false;
    return lower.contains('content="off"') || lower.contains("content='off'");
  }

  /// True when the app asked for an edge-to-edge (immersive) layout.
  static bool wantsEdgeToEdge(String html) {
    final lower = html.toLowerCase();
    if (!lower.contains('applix-edge-to-edge')) return false;
    return lower.contains('content="true"') || lower.contains("content='true'");
  }

  /// Inject the design system into an HTML document.
  static Future<String> applyTo(String html) async {
    final css = await loadCss();
    return inject(html, css);
  }

  /// Pure variant of [applyTo] - inserts the stylesheet after <head>.
  static String inject(String html, String css) {
    if (isOptedOut(html)) return html;
    if (css.isEmpty) return html;
    if (html.contains('id="$styleId"')) return html;
    final block = '<style id="$styleId">\n$css\n</style>';
    if (html.contains('<head>')) {
      return html.replaceFirst('<head>', '<head>\n$block');
    }
    if (html.contains('<head ')) {
      final idx = html.indexOf('>');
      return '${html.substring(0, idx + 1)}\n$block${html.substring(idx + 1)}';
    }
    if (html.contains('<html>')) {
      return html.replaceFirst('<html>', '<html>\n<head>\n$block\n</head>');
    }
    return '$block\n$html';
  }

  /// Per-app theme written next to index.html in the built APK.
  /// The shell reads it and applies the status/navigation bar colors.
  static String buildAppTheme({
    int? accentColor,
    bool edgeToEdge = false,
  }) {
    final accent = accentColor ?? 0xFF4FC3F7;
    final hex = '#${(accent & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    // Light icons on the system bars unless the accent is very light.
    final r = (accent >> 16) & 0xFF;
    final g = (accent >> 8) & 0xFF;
    final b = accent & 0xFF;
    final luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
    final lightIcons = luminance < 0.55;
    return jsonEncode({
      'statusBar': hex,
      'statusBarLight': lightIcons,
      'navBar': hex,
      'navBarLight': lightIcons,
      'edgeToEdge': edgeToEdge,
    });
  }
}
