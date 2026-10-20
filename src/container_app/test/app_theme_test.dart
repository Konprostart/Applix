import 'dart:convert';

import 'package:applix/models/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('app theme', () {
    test('defaults follow the app icon', () {
      const theme = AppTheme();
      expect(theme.isDefault, isTrue);
      expect(theme.splashStyle, 'auto');
      expect(theme.splashShowIcon, isTrue);
      expect(theme.splashBackground, 0);
      expect(theme.statusBarColor, 0);
      expect(theme.navigationBarColor, 0);
    });

    test('survives a json round trip', () {
      const theme = AppTheme(
        splashBackground: 0xFF102030,
        splashStyle: 'gradient',
        splashShowIcon: false,
        statusBarColor: 0xFF445566,
        navigationBarColor: 0xFF778899,
      );
      final back = AppTheme.fromJsonString(theme.toJsonString());
      expect(back.splashBackground, 0xFF102030);
      expect(back.splashStyle, 'gradient');
      expect(back.splashShowIcon, isFalse);
      expect(back.statusBarColor, 0xFF445566);
      expect(back.navigationBarColor, 0xFF778899);
    });

    test('an old app without a theme gets the defaults', () {
      final theme = AppTheme.fromJsonString(null);
      expect(theme.isDefault, isTrue);
      expect(theme.splashStyle, 'auto');
      final empty = AppTheme.fromJsonString('');
      expect(empty.isDefault, isTrue);
    });

    test('broken json falls back to the defaults', () {
      final theme = AppTheme.fromJsonString('{not json');
      expect(theme.isDefault, isTrue);
    });

    test('an unknown style falls back to auto', () {
      final theme = AppTheme.fromJsonString(jsonEncode({'splashStyle': 'neon'}));
      expect(theme.splashStyle, 'auto');
    });

    test('copyWith only changes what is given', () {
      const theme = AppTheme(splashStyle: 'solid', splashBackground: 0xFF112233);
      final next = theme.copyWith(splashShowIcon: false);
      expect(next.splashStyle, 'solid');
      expect(next.splashBackground, 0xFF112233);
      expect(next.splashShowIcon, isFalse);
    });

    test('hexOf formats colors', () {
      expect(AppTheme.hexOf(0), '');
      expect(AppTheme.hexOf(0xFF4FC3F7), '#4fc3f7');
    });
  });
}
