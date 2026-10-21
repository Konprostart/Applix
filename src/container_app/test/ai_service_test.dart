import 'package:flutter_test/flutter_test.dart';
import 'package:applix/services/ai_service.dart';

void main() {
  group('AiService.isTruncatedFinishReason', () {
    test('recognises the cut-off reasons of every provider', () {
      expect(AiService.isTruncatedFinishReason('length'), isTrue);
      expect(AiService.isTruncatedFinishReason('max_tokens'), isTrue);
      expect(AiService.isTruncatedFinishReason('max_output_tokens'), isTrue);
      expect(AiService.isTruncatedFinishReason('LENGTH'), isTrue);
    });

    test('does not flag normal stops', () {
      expect(AiService.isTruncatedFinishReason('stop'), isFalse);
      expect(AiService.isTruncatedFinishReason('end_turn'), isFalse);
      expect(AiService.isTruncatedFinishReason(''), isFalse);
      expect(AiService.isTruncatedFinishReason(null), isFalse);
    });
  });

  group('AiService.contentFromMessage', () {
    test('reads a plain string content', () {
      expect(
          AiService.contentFromMessage({'content': ' hello '}), 'hello');
    });

    test('joins OpenAI content parts', () {
      expect(
        AiService.contentFromMessage({
          'content': [
            {'type': 'text', 'text': 'one'},
            {'type': 'text', 'text': 'two'},
          ],
        }),
        'one\ntwo',
      );
    });

    test('returns empty for an unexpected shape', () {
      expect(AiService.contentFromMessage(null), '');
      expect(AiService.contentFromMessage({'content': 42}), '');
    });
  });
}
