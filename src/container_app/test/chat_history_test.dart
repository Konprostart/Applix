import 'package:applix/services/ai_service.dart';
import 'package:applix/models/ai_provider.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _msg(String role, String content) => ChatMessage(role: role, content: content);

void main() {
  group('conversation trimming', () {
    test('keeps a short history untouched', () {
      final messages = [_msg('user', 'a'), _msg('assistant', 'b')];
      expect(AiService.trimConversation(messages).length, 2);
    });

    test('keeps the first message and the newest ones', () {
      final messages = List.generate(40, (i) => _msg(i.isEven ? 'user' : 'assistant', 'm$i'));
      final trimmed = AiService.trimConversation(messages, max: 10);
      expect(trimmed.length, 10);
      expect(trimmed.first.content, 'm0');
      expect(trimmed.last.content, 'm39');
    });

    test('respects the limit', () {
      final messages = List.generate(20, (i) => _msg('user', 'm$i'));
      expect(AiService.trimConversation(messages, max: 5).length, 5);
    });
  });
}
