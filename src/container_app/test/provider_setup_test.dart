import 'package:applix/models/ai_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('provider configuration', () {
    test('a provider with a key is configured', () {
      final provider = AiProvider.anthropic();
      expect(provider.isConfigured, isFalse);
      provider.apiKey = 'sk-ant-test';
      expect(provider.isConfigured, isTrue);
    });

    test('a custom provider needs a base URL and a model', () {
      final provider = AiProvider.openAICompatible();
      expect(provider.isConfigured, isFalse);
      provider.apiKey = 'not-needed';
      expect(provider.isConfigured, isFalse);
      provider.baseUrl = 'http://192.168.1.20:11434/v1';
      expect(provider.isConfigured, isFalse);
      provider.selectedModel = 'llama3.2';
      expect(provider.isConfigured, isTrue);
    });

    test('the key is never part of the saved json', () {
      final provider = AiProvider.anthropic();
      provider.apiKey = 'sk-secret';
      final json = provider.toJson();
      json.remove('apiKey');
      expect(json.containsKey('apiKey'), isFalse);
      expect(json['id'], 'anthropic');
    });
  });
}
