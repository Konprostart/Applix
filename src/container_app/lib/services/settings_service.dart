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

/// Reads and writes user preferences (AI keys, custom prompt, flags).

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_provider.dart';

class Settings {
  static const showcaseBaseUrl = 'https://raw.githubusercontent.com/Konprostart/Applix-showcase/main';

  static SharedPreferences? _prefs;
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<SharedPreferences> getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── Secure key helpers ──

  static Future<String> _readKey(String id) async {
    try {
      final key = await _secure.read(key: 'apikey_$id');
      return key ?? '';
    } catch (e) {
      debugPrint('[Settings] Secure read failed for $id: $e');
      return '';
    }
  }

  /// Stores a key in the encrypted store. Returns false when the secure store
  /// is unavailable, so the caller can tell the user instead of silently
  /// pretending the key was saved.
  static Future<bool> _writeKey(String id, String apiKey) async {
    try {
      if (apiKey.isNotEmpty) {
        await _secure.write(key: 'apikey_$id', value: apiKey);
      } else {
        await _secure.delete(key: 'apikey_$id');
      }
      return true;
    } catch (e) {
      debugPrint('[Settings] Secure write failed for $id: $e');
      return false;
    }
  }

  /// True when the encrypted key store works on this device.
  static Future<bool> isSecureStoreAvailable() async {
    try {
      await _secure.read(key: 'applix_storage_probe');
      return true;
    } catch (e) {
      debugPrint('[Settings] Secure store unavailable: $e');
      return false;
    }
  }

  // ── Active AI Provider (single, set-and-forget) ──

  static Future<AiProvider?> getActiveProvider() async {
    final prefs = await getPrefs();
    final json = prefs.getString('active_provider');
    if (json == null || json.isEmpty) return null;
    try {
      final provider = AiProvider.fromJson(jsonDecode(json) as Map<String, dynamic>);
      // Restore API key from secure storage
      final secureKey = await _readKey(provider.id);
      if (secureKey.isNotEmpty) {
        provider.apiKey = secureKey;
      }
      return provider;
    } catch (e) {
      debugPrint('[Settings] getActiveProvider failed: $e');
      return null;
    }
  }

  /// Saves the active provider. Returns false when the API key could not be
  /// stored in the encrypted store (the rest of the settings are saved anyway).
  static Future<bool> setActiveProvider(AiProvider provider) async {
    final prefs = await getPrefs();
    // Store API key in secure storage
    final keyStored = await _writeKey(provider.id, provider.apiKey);
    // Strip key from SharedPreferences
    final json = provider.toJson();
    json.remove('apiKey');
    await prefs.setString('active_provider', jsonEncode(json));
    return keyStored;
  }

  // ── AI Providers (legacy multi-provider, kept for migration) ──

  static Future<List<AiProvider>> getProviders() async {
    final prefs = await getPrefs();
    final json = prefs.getString('ai_providers');
    if (json == null || json.isEmpty) {
      return [AiProvider.anthropic(), AiProvider.openRouter()];
    }
    try {
      final list = jsonDecode(json) as List;
      final providers = list.map((j) => AiProvider.fromJson(j as Map<String, dynamic>)).toList();
      for (final p in providers) {
        final secureKey = await _readKey(p.id);
        if (secureKey.isNotEmpty) p.apiKey = secureKey;
      }
      return providers;
    } catch (_) {
      return [AiProvider.anthropic(), AiProvider.openRouter()];
    }
  }

  static Future<bool> saveProviders(List<AiProvider> providers) async {
    final prefs = await getPrefs();
    var allStored = true;
    for (final p in providers) {
      final ok = await _writeKey(p.id, p.apiKey);
      if (!ok) allStored = false;
    }
    final jsonList = providers.map((p) {
      final j = p.toJson();
      j.remove('apiKey');
      return j;
    }).toList();
    await prefs.setString('ai_providers', jsonEncode(jsonList));
    return allStored;
  }

  static Future<AiProvider?> getProvider(String id) async {
    final providers = await getProviders();
    try { return providers.firstWhere((p) => p.id == id); }
    catch (_) { return null; }
  }

  static Future<bool> updateProvider(AiProvider provider) async {
    final providers = await getProviders();
    final idx = providers.indexWhere((p) => p.id == provider.id);
    if (idx >= 0) providers[idx] = provider;
    else providers.add(provider);
    return saveProviders(providers);
  }

  // ── Legacy API key (migrate to providers) ──
  static Future<String> getApiKey() async {
    final prefs = await getPrefs();
    return prefs.getString('api_key') ?? '';
  }

  static Future<void> setApiKey(String key) async {
    final prefs = await getPrefs();
    await prefs.setString('api_key', key);
  }

  static Future<String> getGithubToken() async {
    try { return await _secure.read(key: 'github_token') ?? ''; }
    catch (_) { return ''; }
  }

  static Future<void> setGithubToken(String token) async {
    await _secure.write(key: 'github_token', value: token);
  }

  static Future<String> getModel() async {
    final prefs = await getPrefs();
    return prefs.getString('ai_model') ?? 'claude-sonnet-4-20250514';
  }

  static Future<void> setModel(String model) async {
    final prefs = await getPrefs();
    await prefs.setString('ai_model', model);
  }

  // ── Custom system prompt ──
  static Future<String?> getCustomPrompt() async {
    final prefs = await getPrefs();
    return prefs.getString('custom_prompt');
  }

  static Future<void> setCustomPrompt(String? prompt) async {
    final prefs = await getPrefs();
    if (prompt == null || prompt.isEmpty) {
      await prefs.remove('custom_prompt');
    } else {
      await prefs.setString('custom_prompt', prompt);
    }
  }

  static Future<bool> hasCompletedOnboarding() async {
    final prefs = await getPrefs();
    return prefs.getBool('onboarding_done') ?? false;
  }

  static Future<void> setOnboardingDone() async {
    final prefs = await getPrefs();
    await prefs.setBool('onboarding_done', true);
  }

  static Future<bool> hasCustomPrompt() async {
    final prefs = await getPrefs();
    return prefs.containsKey('custom_prompt');
  }

  static Future<String> getLastSeenPromptHash() async {
    final prefs = await getPrefs();
    return prefs.getString('last_seen_prompt_hash') ?? '';
  }

  static Future<void> setLastSeenPromptHash(String hash) async {
    final prefs = await getPrefs();
    await prefs.setString('last_seen_prompt_hash', hash);
  }

  // ── Update checks ──

  /// When the last GitHub release check ran (null = never).
  static Future<DateTime?> getLastUpdateCheck() async {
    final prefs = await getPrefs();
    final raw = prefs.getString('last_update_check');
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static Future<void> setLastUpdateCheck(DateTime when) async {
    final prefs = await getPrefs();
    await prefs.setString('last_update_check', when.toIso8601String());
  }

  /// ETag of the last release payload - a 304 response costs no API quota.
  static Future<String> getUpdateEtag() async {
    final prefs = await getPrefs();
    return prefs.getString('update_etag') ?? '';
  }

  static Future<void> setUpdateEtag(String etag) async {
    final prefs = await getPrefs();
    await prefs.setString('update_etag', etag);
  }

  /// Cached update descriptor (null when the app is up to date).
  static Future<Map<String, dynamic>?> getCachedUpdate() async {
    final prefs = await getPrefs();
    final raw = prefs.getString('cached_update');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setCachedUpdate(Map<String, dynamic>? update) async {
    final prefs = await getPrefs();
    if (update == null) {
      await prefs.remove('cached_update');
    } else {
      await prefs.setString('cached_update', jsonEncode(update));
    }
  }

  // ── Manual prompt draft ──
  // The prompt generated in the Manual flow is kept on the device so it is not
  // lost when the user leaves the screen or restarts the app.

  static Future<void> savePromptDraft({
    required String full,
    required String linked,
    required String description,
  }) async {
    final prefs = await getPrefs();
    await prefs.setString('prompt_draft_full', full);
    await prefs.setString('prompt_draft_linked', linked);
    await prefs.setString('prompt_draft_desc', description);
  }

  static Future<Map<String, String>> getPromptDraft() async {
    final prefs = await getPrefs();
    return {
      'full': prefs.getString('prompt_draft_full') ?? '',
      'linked': prefs.getString('prompt_draft_linked') ?? '',
      'description': prefs.getString('prompt_draft_desc') ?? '',
    };
  }

  // ── Package prefix ──
  static const int maxPrefixLength = 20;

  static Future<String> getPackagePrefix() async {
    final prefs = await getPrefs();
    var prefix = prefs.getString('package_prefix');
    if (prefix == null || prefix.isEmpty || prefix == 'com.iappyx.g' || prefix == 'com.applix') {
      // First launch or legacy default
      prefix = 'applix';
      await prefs.setString('package_prefix', prefix);
    }
    if (!validatePrefix(prefix)) {
      prefix = 'applix';
      await prefs.setString('package_prefix', prefix);
    }
    return prefix;
  }

  static Future<void> setPackagePrefix(String prefix) async {
    final prefs = await getPrefs();
    if (validatePrefix(prefix)) {
      await prefs.setString('package_prefix', prefix);
    }
  }

  static bool validatePrefix(String prefix) {
    if (prefix.isEmpty || prefix.length > maxPrefixLength) return false;
    if (!RegExp(r'^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)*$').hasMatch(prefix)) return false;
    return true;
  }

  // ── CSS Style Preset ──

  static const stylePresets = ['default', 'material', 'glassmorphic', 'minimal', 'dynamic'];
  static const styleLabels = {
    'default': 'None',
    'material': 'Material',
    'glassmorphic': 'Glassmorphic',
    'minimal': 'Minimal',
    'dynamic': 'Dynamic',
  };

  static Future<String> getCssStylePreset() async {
    final prefs = await getPrefs();
    return prefs.getString('css_style_preset') ?? 'default';
  }

  static Future<void> setCssStylePreset(String preset) async {
    final prefs = await getPrefs();
    await prefs.setString('css_style_preset', preset);
  }

  /// Human readable name of a style preset.
  static String getStyleLabel(String preset) {
    if (preset == 'default') return 'Applix UI Kit (recommended)';
    return (styleLabels[preset] as String?) ?? 'Applix UI Kit (recommended)';
  }

  static String getCssForPreset(String preset) {
    switch (preset) {
      case 'material':
        return '''
## CSS Style: Material
Layer these Material touches on top of the Applix UI Kit - keep every .ax-* class:
- Typography: `font-family: system-ui, Roboto, 'Noto Color Emoji', sans-serif`
- `touch-action: manipulation` on interactive elements
- Keep 48px minimum touch targets
- Buttons: use `.ax-btn` and add elevation `box-shadow: var(--ax-shadow-2)`; active state `var(--ax-shadow-3)` with `transform: translateY(-1px)`
- Inputs: keep `.ax-input`; focus ring uses `--ax-primary`
- Cards: `.ax-card` with `box-shadow: var(--ax-shadow-2)`
- Transitions: `var(--ax-fast) var(--ax-ease)`
- Corners: `--ax-radius` for cards, `--ax-radius-pill` for action buttons
- Never hardcode colours; use `--ax-*` tokens only
''';
      case 'glassmorphic':
        return '''
## CSS Style: Glassmorphic
Layer these glass effects on top of the Applix UI Kit - keep every .ax-* class:
- Surfaces: `background: color-mix(in srgb, var(--ax-surface) 74%, transparent); backdrop-filter: blur(16px); -webkit-backdrop-filter: blur(16px); border: 1px solid var(--ax-border-strong)`
- Buttons: translucent `--ax-primary` with a soft `--ax-shadow-2`; no transform on active
- Inputs: translucent `--ax-surface-2` with `--ax-border`; focus ring `--ax-primary`
- Subtle accent glow: `box-shadow: 0 0 24px color-mix(in srgb, var(--ax-primary) 18%, transparent)` on hero cards
- Typography: `system-ui, Roboto, sans-serif`
- `touch-action: manipulation` on interactive elements
- Rounded corners: `--ax-radius-lg` for cards, `--ax-radius` for buttons
- Never hardcode colours; use `--ax-*` tokens only
''';
      case 'minimal':
        return '''
## CSS Style: Minimal
Layer this minimal treatment on top of the Applix UI Kit - keep every .ax-* class:
- Maximum whitespace; fewer borders, no gradients, no blur
- Cards: `background: var(--ax-surface); border: 1px solid var(--ax-border); box-shadow: none`
- Buttons: `.ax-btn--ghost` as the default; primary action keeps `.ax-btn`
- Inputs: `.ax-input` with a 1px `--ax-border` bottom border and transparent background
- Typography: `system-ui, Roboto, sans-serif`; weight 300 for body, 600 for headings
- Padding: `var(--ax-5)` inside cards, `var(--ax-3)` between elements
- Transitions: `var(--ax-fast) var(--ax-ease)`
- Rounded corners: `--ax-radius-sm`
- Never hardcode colours; use `--ax-*` tokens only
''';
      case 'dynamic':
        return '''
## CSS Style: Dynamic (Material You)
Drive the Applix UI Kit tokens from the device theme - keep every .ax-* class.
In `onReady`, call `JSON.parse(iappyx.device.getThemeColors())` to get:
`{primary, primaryLight, primaryDark, secondary, tertiary, neutral, neutralLight, neutralDark, background, surface, isDark, dynamic}`
and map them onto the kit tokens:
```javascript
var t = JSON.parse(iappyx.device.getThemeColors());
var s = document.documentElement.style;
s.setProperty('--ax-primary', t.primary);
s.setProperty('--ax-primary-press', t.primaryDark);
s.setProperty('--ax-primary-2', t.secondary);
s.setProperty('--ax-bg', t.background);
s.setProperty('--ax-surface', t.surface);
s.setProperty('--ax-surface-2', t.surface);
s.setProperty('--ax-text', t.isDark ? t.neutralLight : t.neutralDark);
s.setProperty('--ax-text-dim', t.neutral);
s.setProperty('--ax-on-primary', t.onPrimary);
s.setProperty('--ax-on-surface', t.onSurface);
```
- Use `--ax-*` tokens everywhere; never hardcode background, text or accent colours
- `touch-action: manipulation` on interactive elements
- Transitions: `var(--ax-fast) var(--ax-ease)`
- Corners: `--ax-radius` for cards and buttons
- Use `.ax-check` / `.ax-radio` / `.ax-switch`; do not fall back to unstyled native controls
''';
      default:
        return '';
    }
  }
}
