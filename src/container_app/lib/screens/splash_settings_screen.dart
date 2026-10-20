// MIT License — Copyright (c) 2026 iappyx

import 'package:flutter/material.dart';

import '../models/app_theme.dart';
import '../models/icon_config.dart';

/// Lets the user design the launch (splash) screen and the system bars of an
/// app. Everything is optional: the defaults follow the app icon, so apps that
/// were created before this screen existed keep their look.
class SplashSettingsScreen extends StatefulWidget {
  final AppTheme theme;
  final IconConfig icon;

  const SplashSettingsScreen({
    super.key,
    required this.theme,
    required this.icon,
  });

  @override
  State<SplashSettingsScreen> createState() => _SplashSettingsScreenState();
}

class _SplashSettingsScreenState extends State<SplashSettingsScreen> {
  late AppTheme _theme = widget.theme;

  static const _colors = [
    0xFF0D0D1A, 0xFF12122A, 0xFF1A1A2E, 0xFF0F3460, 0xFF4FC3F7,
    0xFF1B1B3A, 0xFF2B1A55, 0xFF4B1F7A, 0xFF1565C0, 0xFF2E7D32,
    0xFFC62828, 0xFFEF6C00, 0xFFF2F4F8, 0xFFFFFFFF,
  ];

  @override
  Widget build(BuildContext context) {
    final iconColors = widget.icon.bgGradient != null && widget.icon.bgGradient!.length >= 2
        ? widget.icon.bgGradient!
        : [widget.icon.bgColor, widget.icon.bgColor];

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        title: const Text('Splash & Bars', style: TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _theme),
            child: const Text('Save', style: TextStyle(color: Color(0xFF4FC3F7), fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _preview(iconColors),
          const SizedBox(height: 20),
          const Text('Splash style',
              style: TextStyle(fontSize: 13, color: Colors.white54)),
          const SizedBox(height: 8),
          Row(children: AppTheme.styles.map((style) {
            final selected = _theme.splashStyle == style;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _theme = _theme.copyWith(splashStyle: style)),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF0F3460) : const Color(0xFF12121F),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: selected ? const Color(0xFF4FC3F7) : Colors.white12),
                  ),
                  child: Center(
                    child: Text(style,
                        style: TextStyle(
                            fontSize: 12,
                            color: selected ? Colors.white : Colors.white54)),
                  ),
                ),
              ),
            );
          }).toList()),
          const SizedBox(height: 6),
          Text(
            _theme.splashStyle == 'auto'
                ? 'A solid color taken from the app icon.'
                : _theme.splashStyle == 'solid'
                    ? 'One fixed color for the launch screen.'
                    : _theme.splashStyle == 'gradient'
                        ? 'The gradient of the app icon.'
                        : 'The app icon fills the launch screen.',
            style: const TextStyle(fontSize: 11, color: Colors.white38),
          ),
          const SizedBox(height: 16),
          if (_theme.splashStyle == 'solid') ...[
            const Text('Splash color',
                style: TextStyle(fontSize: 13, color: Colors.white54)),
            const SizedBox(height: 8),
            _colorRow(
              _theme.splashBackground,
              (color) => setState(
                  () => _theme = _theme.copyWith(splashBackground: color)),
            ),
            const SizedBox(height: 16),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _theme.splashShowIcon,
            activeColor: const Color(0xFF4FC3F7),
            title: const Text('Show the app icon in the splash',
                style: TextStyle(fontSize: 14)),
            onChanged: (v) =>
                setState(() => _theme = _theme.copyWith(splashShowIcon: v)),
          ),
          const Divider(height: 28, color: Color(0xFF1A1A2E)),
          const Text('System bars',
              style: TextStyle(fontSize: 13, color: Colors.white54)),
          const SizedBox(height: 4),
          const Text('Leave "follow the icon" to keep the default colors.',
              style: TextStyle(fontSize: 11, color: Colors.white38)),
          const SizedBox(height: 12),
          const Text('Status bar',
              style: TextStyle(fontSize: 12, color: Colors.white38)),
          const SizedBox(height: 6),
          _colorRow(
            _theme.statusBarColor,
            (color) =>
                setState(() => _theme = _theme.copyWith(statusBarColor: color)),
            followLabel: 'follow the icon',
          ),
          const SizedBox(height: 14),
          const Text('Navigation bar',
              style: TextStyle(fontSize: 12, color: Colors.white38)),
          const SizedBox(height: 6),
          _colorRow(
            _theme.navigationBarColor,
            (color) => setState(
                () => _theme = _theme.copyWith(navigationBarColor: color)),
            followLabel: 'follow the icon',
          ),
        ],
      ),
    );
  }

  Widget _preview(List<int> iconColors) {
    final style = _theme.splashStyle;
    Color? solid;
    if (style == 'solid' && _theme.splashBackground != 0) {
      solid = Color(_theme.splashBackground);
    } else if (style == 'auto' || style == 'solid') {
      solid = Color(iconColors.first);
    }
    final gradient = style == 'gradient'
        ? LinearGradient(
            colors: [Color(iconColors.first), Color(iconColors.last)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : null;

    return Container(
      height: 190,
      width: double.infinity,
      decoration: BoxDecoration(
        color: solid,
        gradient: gradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Center(
        child: _theme.splashShowIcon
            ? Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: Color(iconColors.first),
                  gradient: widget.icon.bgGradient != null
                      ? LinearGradient(
                          colors: [
                            Color(widget.icon.bgGradient![0]),
                            Color(widget.icon.bgGradient![1]),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: Text(
                    widget.icon.elements.isNotEmpty
                        ? widget.icon.elements.first.content
                        : 'A',
                    style: const TextStyle(fontSize: 34, color: Colors.white),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _colorRow(int current, void Function(int) onPick,
      {String followLabel = 'follow the icon'}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => onPick(0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: current == 0 ? const Color(0xFF0F3460) : const Color(0xFF12121F),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: current == 0 ? const Color(0xFF4FC3F7) : Colors.white12),
            ),
            child: Text(followLabel,
                style: TextStyle(
                    fontSize: 11,
                    color: current == 0 ? Colors.white : Colors.white54)),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _colors.map((c) {
            final selected = current == c;
            return GestureDetector(
              onTap: () => onPick(c),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Color(c),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: selected ? const Color(0xFF4FC3F7) : Colors.white12,
                      width: selected ? 2 : 1),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
