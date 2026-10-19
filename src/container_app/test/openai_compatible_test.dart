import 'package:flutter_test/flutter_test.dart';
import 'package:applix/services/openai_compatible.dart';

void main() {
  group('endpoints', () {
    test('server root appends /v1', () {
      expect(
        OpenAICompatible.chatEndpoint('http://10.0.0.5:11434').toString(),
        'http://10.0.0.5:11434/v1/chat/completions',
      );
      expect(
        OpenAICompatible.modelsEndpoint('http://10.0.0.5:11434').toString(),
        'http://10.0.0.5:11434/v1/models',
      );
    });

    test('/v1 base appends paths and trims trailing slashes', () {
      expect(
        OpenAICompatible.chatEndpoint('http://host:1234/v1/').toString(),
        'http://host:1234/v1/chat/completions',
      );
      expect(
        OpenAICompatible.modelsEndpoint('http://host:1234/v1/').toString(),
        'http://host:1234/v1/models',
      );
    });

    test('full chat URL is used as-is', () {
      const url = 'http://host:8000/v1/chat/completions';
      expect(OpenAICompatible.chatEndpoint(url).toString(), url);
      expect(
        OpenAICompatible.modelsEndpoint(url).toString(),
        'http://host:8000/v1/models',
      );
    });

    test('empty URL throws', () {
      expect(() => OpenAICompatible.chatEndpoint('  '), throwsFormatException);
      expect(() => OpenAICompatible.modelsEndpoint(''), throwsFormatException);
    });
  });

  group('parsing', () {
    test('parse models, fallback name and sort', () {
      final models = OpenAICompatible.parseModels(
        '{"data":[{"id":"zeta"},{"id":"alpha","name":"Alpha"}]}',
      );
      expect(models.map((m) => m.id).toList(), ['alpha', 'zeta']);
      expect(models.first.name, 'Alpha');
      expect(models.last.name, 'zeta');
    });

    test('parse completion', () {
      expect(
        OpenAICompatible.parseCompletion(
          '{"choices":[{"message":{"content":"hello"}}]}',
        ),
        'hello',
      );
    });

    test('malformed completion throws', () {
      expect(
        () => OpenAICompatible.parseCompletion('{"choices":[]}'),
        throwsFormatException,
      );
    });

    test('parse API errors from JSON and plain text', () {
      expect(
        OpenAICompatible.parseApiError(401, '{"error":{"message":"bad key"}}'),
        'bad key',
      );
      expect(
        OpenAICompatible.parseApiError(500, 'oops'),
        'API error 500: oops',
      );
    });
  });
}
