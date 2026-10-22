import 'dart:convert';

import 'package:applix/models/ai_provider.dart';
import 'package:applix/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('developer mode', () {
    test('defaults to off and round trips', () async {
      expect(await Settings.isDeveloperMode(), isFalse);
      await Settings.setDeveloperMode(true);
      expect(await Settings.isDeveloperMode(), isTrue);
      await Settings.setDeveloperMode(false);
      expect(await Settings.isDeveloperMode(), isFalse);
    });
  });

  group('prompt draft', () {
    test('round trips the manual prompt', () async {
      await Settings.savePromptDraft(
        full: 'FULL PROMPT',
        linked: 'LINKED PROMPT',
        description: 'a weather app',
      );
      final draft = await Settings.getPromptDraft();
      expect(draft['full'], 'FULL PROMPT');
      expect(draft['linked'], 'LINKED PROMPT');
      expect(draft['description'], 'a weather app');
    });

    test('is empty when nothing was saved', () async {
      // Settings caches the SharedPreferences instance, so the values are
      // cleared explicitly instead of relying on the mock reset.
      final prefs = await Settings.getPrefs();
      await prefs.remove('prompt_draft_full');
      await prefs.remove('prompt_draft_linked');
      await prefs.remove('prompt_draft_desc');
      final draft = await Settings.getPromptDraft();
      expect(draft['full'], '');
      expect(draft['linked'], '');
      expect(draft['description'], '');
    });
  });

  group('provider persistence', () {
    test('the api key never lands in shared preferences', () async {
      final provider = AiProvider.openAICompatible();
      provider.apiKey = 'sk-secret-value';
      provider.baseUrl = 'http://192.168.1.20:11434/v1';
      provider.selectedModel = 'llama3.2';
      await Settings.setActiveProvider(provider);

      final prefs = await Settings.getPrefs();
      final raw = prefs.getString('active_provider');
      expect(raw, isNotNull);
      expect(raw, isNot(contains('sk-secret-value')));
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      expect(json['baseUrl'], 'http://192.168.1.20:11434/v1');
      expect(json['selectedModel'], 'llama3.2');
      expect(json.containsKey('apiKey'), isFalse);
    });

    test('the active provider is restored from shared preferences', () async {
      final provider = AiProvider.openAICompatible();
      provider.baseUrl = 'http://localhost:1234/v1';
      provider.selectedModel = 'qwen2.5';
      await Settings.setActiveProvider(provider);

      final restored = await Settings.getActiveProvider();
      expect(restored, isNotNull);
      expect(restored!.id, 'openai_compatible');
      expect(restored.baseUrl, 'http://localhost:1234/v1');
      expect(restored.selectedModel, 'qwen2.5');
    });
  });
}
