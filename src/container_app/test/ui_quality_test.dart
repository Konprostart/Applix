import 'package:applix/models/icon_config.dart';
import 'package:applix/services/ui_auditor.dart';
import 'package:applix/services/ui_kit.dart';
import 'package:flutter_test/flutter_test.dart';

const _goodHtml = '''<!DOCTYPE html>
<html><head>
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no,viewport-fit=cover">
<meta name="theme-color" content="#0d0d1a">
<style>body{font-family:system-ui,Roboto,sans-serif}</style>
</head><body>
<div class="ax-appbar"><div class="ax-appbar__title">App</div></div>
<div class="ax-page">
  <button class="ax-btn">Add</button>
  <input class="ax-input">
  <div class="ax-empty"><div class="ax-empty__title">Nothing here</div></div>
</div>
</body></html>''';

void main() {
  group('UiAuditor', () {
    test('a well formed app has no violations', () {
      expect(UiAuditor.audit(_goodHtml), isEmpty);
    });

    test('flags a plain web page', () {
      const plain = '<html><head><title>x</title></head><body><button>Hi</button></body></html>';
      final codes = UiAuditor.audit(plain).map((v) => v.code).toSet();
      expect(codes, contains('viewport'));
      expect(codes, contains('ui-kit'));
      expect(codes, contains('theme-color'));
      expect(codes, contains('touch-target'));
    });

    test('flags a missing viewport-fit', () {
      const html = '<html><head><meta name="viewport" content="width=device-width,user-scalable=no">'
          '</head><body><div class="ax-page"><button class="ax-btn">a</button></div></body></html>';
      final codes = UiAuditor.audit(html).map((v) => v.code).toSet();
      expect(codes, contains('viewport-fit'));
      expect(codes, isNot(contains('ui-kit')));
    });

    test('flags the apple font stack', () {
      const html = '<html><head><meta name="viewport" content="user-scalable=no,viewport-fit=cover">'
          '<meta name="theme-color" content="#000"></head><body>'
          '<div class="ax-page"><button class="ax-btn">a</button></div>'
          '<style>body{font-family:-apple-system}</style></body></html>';
      final codes = UiAuditor.audit(html).map((v) => v.code).toSet();
      expect(codes, contains('font'));
    });

    test('empty html is not audited', () {
      expect(UiAuditor.audit(''), isEmpty);
    });

    test('formats the issues for an AI prompt', () {
      final message = UiAuditor.buildPolishMessage(
          [const UiViolation('viewport', 'Missing viewport meta')]);
      expect(message, contains('Missing viewport meta'));
      expect(message, contains('native Android app'));
    });
  });

  group('UiKit', () {
    test('detects the opt-out meta tag', () {
      expect(UiKit.isOptedOut('<meta name="applix-ui" content="off">'), isTrue);
      expect(UiKit.isOptedOut('<meta name="applix-ui" content="on">'), isFalse);
      expect(UiKit.isOptedOut('<html></html>'), isFalse);
    });

    test('detects the edge-to-edge opt-in', () {
      expect(UiKit.wantsEdgeToEdge('<meta name="applix-edge-to-edge" content="true">'), isTrue);
      expect(UiKit.wantsEdgeToEdge('<meta name="applix-edge-to-edge" content="false">'), isFalse);
      expect(UiKit.wantsEdgeToEdge('<html></html>'), isFalse);
    });

    test('injects the stylesheet after the head', () {
      final out = UiKit.inject('<html><head><title>x</title></head><body></body></html>', 'body{}');
      expect(out, contains('<style id="applix-ui-kit">'));
      expect(out.indexOf('<head>'), lessThan(out.indexOf('<style id="applix-ui-kit">')));
    });

    test('does not inject twice', () {
      final once = UiKit.inject('<html><head></head></html>', 'body{}');
      final twice = UiKit.inject(once, 'body{}');
      expect(twice, once);
    });

    test('respects the opt-out', () {
      const html = '<html><head><meta name="applix-ui" content="off"></head></html>';
      expect(UiKit.inject(html, 'body{}'), html);
    });

    test('creates a head when the document has none', () {
      final out = UiKit.inject('<html><body></body></html>', 'body{}');
      expect(out, contains('<style id="applix-ui-kit">'));
      expect(out, contains('</head>'));
    });

    test('builds a valid app theme', () {
      final json = UiKit.buildAppTheme(accentColor: 0xFF4FC3F7, edgeToEdge: true);
      expect(json, contains('"edgeToEdge":true'));
      expect(json, contains('statusBar'));
      expect(json, contains('navBar'));
    });
  });

  group('auto icon', () {
    test('default icon uses a deterministic gradient', () {
      final a = IconConfig.defaultFor('My App');
      final b = IconConfig.defaultFor('My App');
      expect(a.bgGradient, isNotNull);
      expect(a.bgGradient!.length, 2);
      expect(a.bgGradient, b.bgGradient);
      expect(a.elements.first.content, 'M');
      expect(a.elements.first.isText, isTrue);
    });

    test('different names get different gradients', () {
      final a = IconConfig.defaultFor('Alpha');
      final b = IconConfig.defaultFor('Zulu');
      expect(a.bgGradient, isNot(b.bgGradient));
    });
  });
}
