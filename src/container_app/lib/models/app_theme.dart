// MIT License — Copyright (c) 2026 iappyx

import 'dart:convert';

/// Per-app look of the launch (splash) screen and the system bars.
///
/// Everything is optional: a value of 0 (or the default style) means "follow
/// the app icon", so apps that were created before these options existed keep
/// working exactly as before.
class AppTheme {
  /// Background color of the splash screen. 0 = take it from the app icon.
  final int splashBackground;

  /// How the splash is painted:
  ///   'auto'     - a solid color derived from the app icon
  ///   'solid'    - the solid splashBackground color
  ///   'gradient' - the gradient of the app icon
  ///   'icon'     - the app icon fills the background
  final String splashStyle;

  /// Whether the app icon is shown in the middle of the splash screen.
  final bool splashShowIcon;

  /// Color of the status bar. 0 = follow the app icon.
  final int statusBarColor;

  /// Color of the navigation bar. 0 = follow the app icon.
  final int navigationBarColor;

  const AppTheme({
    this.splashBackground = 0,
    this.splashStyle = 'auto',
    this.splashShowIcon = true,
    this.statusBarColor = 0,
    this.navigationBarColor = 0,
  });

  static const styles = ['auto', 'solid', 'gradient', 'icon'];

  bool get isDefault =>
      splashBackground == 0 &&
      splashStyle == 'auto' &&
      splashShowIcon &&
      statusBarColor == 0 &&
      navigationBarColor == 0;

  AppTheme copyWith({
    int? splashBackground,
    String? splashStyle,
    bool? splashShowIcon,
    int? statusBarColor,
    int? navigationBarColor,
  }) =>
      AppTheme(
        splashBackground: splashBackground ?? this.splashBackground,
        splashStyle: splashStyle ?? this.splashStyle,
        splashShowIcon: splashShowIcon ?? this.splashShowIcon,
        statusBarColor: statusBarColor ?? this.statusBarColor,
        navigationBarColor: navigationBarColor ?? this.navigationBarColor,
      );

  Map<String, dynamic> toJson() => {
        'splashBackground': splashBackground,
        'splashStyle': splashStyle,
        'splashShowIcon': splashShowIcon,
        'statusBarColor': statusBarColor,
        'navigationBarColor': navigationBarColor,
      };

  String toJsonString() => jsonEncode(toJson());

  factory AppTheme.fromJsonString(String? json) {
    if (json == null || json.trim().isEmpty) return const AppTheme();
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return const AppTheme();
      final style = decoded['splashStyle'] as String? ?? 'auto';
      return AppTheme(
        splashBackground: (decoded['splashBackground'] as num?)?.toInt() ?? 0,
        splashStyle: styles.contains(style) ? style : 'auto',
        splashShowIcon: decoded['splashShowIcon'] as bool? ?? true,
        statusBarColor: (decoded['statusBarColor'] as num?)?.toInt() ?? 0,
        navigationBarColor: (decoded['navigationBarColor'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return const AppTheme();
    }
  }

  /// A readable hex color for a color value (0 = none).
  static String hexOf(int color) {
    if (color == 0) return '';
    return '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }
}
