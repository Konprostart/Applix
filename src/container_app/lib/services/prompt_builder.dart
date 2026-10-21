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

/// Assembles the system prompt sent to the AI, merging default and custom parts.

import 'package:flutter/services.dart' show rootBundle;
import 'settings_service.dart';
import 'app_plan.dart';

class PromptBuilder {
  static String? _defaultPrompt;
  static String? _defaultPlannerPrompt;

  static Future<String> getSystemPrompt() async {
    // Check for custom prompt first
    final custom = await Settings.getCustomPrompt();
    if (custom != null && custom.isNotEmpty) return custom;
    // Fall back to bundled default
    _defaultPrompt ??= await rootBundle.loadString('assets/system_prompt.md');
    return _defaultPrompt!;
  }

  static Future<String> getDefaultPrompt() async {
    _defaultPrompt ??= await rootBundle.loadString('assets/system_prompt.md');
    return _defaultPrompt!;
  }

  /// Returns true if user has a custom prompt AND the bundled prompt has changed since they last reset.
  static Future<bool> isPromptOutdated() async {
    final hasCustom = await Settings.hasCustomPrompt();
    if (!hasCustom) return false;
    final bundled = await getDefaultPrompt();
    final hash = '${bundled.length}_${bundled.codeUnits.fold<int>(0, (a, b) => a + b)}';
    final lastSeen = await Settings.getLastSeenPromptHash();
    return lastSeen.isNotEmpty && lastSeen != hash;
  }

  /// Call when user resets to default or on first launch to store the current bundled hash.
  static Future<void> markPromptAsSeen() async {
    final bundled = await getDefaultPrompt();
    final hash = '${bundled.length}_${bundled.codeUnits.fold<int>(0, (a, b) => a + b)}';
    await Settings.setLastSeenPromptHash(hash);
  }

  /// Returns today's date as an ISO version tag (e.g. "v2026-04-15"). Computed
  /// fresh per call so the prompt always carries the current date — this is a
  /// deliberate signal to the AI: "this is recent, ignore older training data".
  static String _todayVersionTag() {
    final now = DateTime.now();
    String pad(int n) => n < 10 ? '0$n' : '$n';
    return 'v${now.year}-${pad(now.month)}-${pad(now.day)}';
  }

  /// Short "linked" prompt variant for the Manual flow. Works with AIs that can
  /// fetch URLs autonomously (Claude.ai, ChatGPT with browsing, Gemini). Contains
  /// the task, the canonical spec URL, and just enough core rules that the model
  /// can still produce something sane if the fetch fails.
  ///
  /// Keep this under ~600 chars so it fits in any chat tool's paste limit.
  static Future<String> buildLinkedPrompt({
    required String appName,
    required String description,
    String? existingHtml,
  }) async {
    final versionTag = _todayVersionTag();
    final update = existingHtml != null && existingHtml.trim().startsWith('<');
    final buf = StringBuffer();
    buf.writeln('Build a complete single-file HTML app for Applix ($versionTag).');
    buf.writeln();
    buf.writeln('App name: $appName');
    buf.writeln('Task: $description');
    buf.writeln();
    buf.writeln('The full Applix spec (bridge reference + rules) is here:');
    buf.writeln('https://raw.githubusercontent.com/Konprostart/Applix/main/SPEC.md');
    buf.writeln('Fetch it before generating. Only use iappyx.* methods documented there.');
    buf.writeln();
    buf.writeln('Core rules (in case you cannot fetch):');
    buf.writeln('- Return ONLY the complete HTML file. First char `<`, last char `>`. No fences, no prose.');
    buf.writeln('- Wait for the bridge with a poll: `function _init(){if(typeof iappyx===\'undefined\'){setTimeout(_init,50);return}onReady()}; window.addEventListener(\'load\',function(){setTimeout(_init,200)})`.');
    buf.writeln('- Use `iappyx.save(k,v)`/`iappyx.load(k)` for storage (NOT localStorage).');
    buf.writeln('- Use `iappyx.httpClient.request(optsJson, cbId)` for external APIs (fetch() fails from file://).');
    buf.writeln('- No `alert()`/`confirm()`/`prompt()` — they are blocked in WebView; use HTML modals.');
    buf.writeln('- Do NOT invent iappyx.* methods. If a capability is not in the spec, it does not exist.');
    if (update) {
      buf.writeln();
      buf.writeln('Current app code (update it, preserving existing functionality unless the task asks to change it):');
      buf.writeln('```html');
      buf.write(existingHtml);
      buf.writeln();
      buf.writeln('```');
      buf.writeln('Re-verify every iappyx.* call in the existing code against the spec; earlier AI generations may have hallucinated methods.');
    }
    return buf.toString();
  }

  /// The design contract every generated app has to follow. It turns a vague
  /// description into a concrete, native-looking app.
  static String _designContract(String appName, String stylePreset) {
    final styleLabel = Settings.getStyleLabel(stylePreset);
    return '''DESIGN CONTRACT - the app must look like a native Android app, not a web page:

- Style: $styleLabel
- Build the whole UI from the Applix UI Kit classes: .ax-page (page layout), .ax-appbar
  (top bar), .ax-card, .ax-list + .ax-row (list rows), .ax-btn (buttons), .ax-fab,
  .ax-input + .ax-field (inputs), .ax-select, .ax-check, .ax-radio, .ax-search,
  .ax-stepper, .ax-chip, .ax-switch, .ax-empty (empty state), .ax-skeleton
  (loading state), .ax-toast (messages), .ax-sheet (bottom sheet), .ax-stat,
  .ax-table, .ax-chart, .ax-sparkline, .ax-donut, .ax-icon
- Import icons, charts and overlays from './applix-ui.js' (icon, mountIcons,
  sparkline, barChart, donut, toast, openSheet, confirmDialog, mountTabs,
  mountBottomNav, mountSegmented, stagger) instead of hand-writing them
- Never invent your own colour or spacing system - use the --ax-* design tokens
- Single column, 16px side padding, 48px minimum touch targets, no horizontal scrolling
- Type scale: 1.6rem headings, 1rem body, 0.8rem labels
- Every screen needs a top bar, a real empty state and a loading state
- Start with 3-8 realistic seed records and persist every mutation; no dead controls
- Every data app gets a real chart (sparkline/barChart/donut) and .ax-num numbers
- The app is called "$appName" - the title bar shows that name''';
  }

  static String _designContractFor(String appName, String stylePreset) =>
      _designContract(appName, stylePreset);

  /// Planner system prompt. Kept tiny so planning is fast and cheap.
  static Future<String> getPlannerPrompt() async {
    _defaultPlannerPrompt ??= await rootBundle.loadString('assets/planner_prompt.md');
    return _defaultPlannerPrompt!;
  }

  static Future<String> buildPlannerRequest({
    required String appName,
    required String description,
  }) async {
    return 'App name: $appName\nDescription: $description';
  }

  /// Builds the user-facing generation request without the system prompt.
  /// Used by in-app API generation (the system prompt is sent separately) and by
  /// [buildPrompt] for the manual copy/paste flow.
  static Future<String> buildRequest({
    required String appName,
    required String description,
    String? existingHtml,
    AppPlan? plan,
    String? styleCss,
  }) async {
    final versionTag = _todayVersionTag();
    final stylePreset = await Settings.getCssStylePreset();
    final css = styleCss ?? Settings.getCssForPreset(stylePreset);
    final contract = _designContractFor(appName, stylePreset);
    final isUpdate = existingHtml != null && existingHtml.trim().startsWith('<');
    final buf = StringBuffer();
    buf.writeln(contract);
    if (css.isNotEmpty) {
      buf.writeln();
      buf.writeln(css);
    }
    if (plan != null && !plan.isEmpty) {
      buf.writeln();
      buf.writeln(plan.toPromptBlock());
    }
    buf.writeln();

    if (isUpdate) {
      buf.writeln('APP UPDATE REQUEST:');
      buf.writeln('App name: $appName');
      buf.writeln('Description: $description');
      buf.writeln();
      buf.writeln('Here is the current app code:');
      buf.writeln('```html');
      buf.writeln(existingHtml);
      buf.writeln('```');
      buf.writeln();
      buf.writeln('Update this app based on the description. Preserve all existing functionality unless the description explicitly asks to change it. Return the complete updated app (single HTML file or multi-file JSON project, matching the existing shape).');
    } else {
      buf.writeln('APP REQUEST:');
      buf.writeln('App name: $appName');
      buf.writeln('Description: $description');
      buf.writeln();
      buf.writeln('Generate a complete, fully functional app matching this description. Apply every technical requirement from the instructions above. Use realistic seed data, wire every control, persist state, and self-review before answering.');
    }
    buf.writeln();
    buf.writeln('REMINDER (Applix system prompt $versionTag): every `iappyx.*` method you use must be verified against the Bridge reference above. If you are uncertain whether a method exists, it does not - pick one that IS listed. Also re-verify calls already present in existing code.');
    return buf.toString();
  }

  /// Full prompt for the manual copy/paste flow: system prompt + request.
  static Future<String> buildPrompt({
    required String appName,
    required String description,
    String? existingHtml,
    AppPlan? plan,
  }) async {
    var systemPrompt = await getSystemPrompt();
    final versionTag = _todayVersionTag();
    systemPrompt = systemPrompt.replaceAll('{{VERSION_TAG}}', versionTag);
    final stylePreset = await Settings.getCssStylePreset();
    final styleCss = Settings.getCssForPreset(stylePreset);
    final request = await buildRequest(
      appName: appName,
      description: description,
      existingHtml: existingHtml,
      plan: plan,
      styleCss: styleCss,
    );
    return '$systemPrompt\n\n---\n\n$request';
  }
}
