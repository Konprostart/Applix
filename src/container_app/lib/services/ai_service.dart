import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/ai_provider.dart';
import 'openai_compatible.dart';

/// The provider stopped because it hit the output limit. Treating that as a
/// finished app silently ships a cut-off document, so callers must see it.
class AiTruncatedException implements Exception {
  final String message;
  const AiTruncatedException(this.message);
  @override
  String toString() => message;
}

class AiService {
  /// Keeps a chat history bounded. Every message carries the whole app code,
  /// so an endless chat would grow the memory (and every request) without
  /// limit. The first message is always kept - it holds the original task.
  static List<ChatMessage> trimConversation(List<ChatMessage> messages, {int max = 14}) {
    if (messages.length <= max || max < 2) return messages;
    final first = messages.first;
    final tail = messages.sublist(messages.length - (max - 1));
    return [first, ...tail];
  }

  /// True when a provider finish/stop reason means the answer was cut off.
  static bool isTruncatedFinishReason(String? reason) {
    final value = (reason ?? '').trim().toLowerCase();
    return value == 'length' ||
        value == 'max_tokens' ||
        value == 'max_output_tokens';
  }

  /// Message content from the OpenAI/OpenRouter shape. Some servers return a
  /// list of content parts instead of a plain string.
  static String contentFromMessage(Object? message) {
    if (message is! Map) return '';
    final content = message['content'];
    if (content is String) return content.trim();
    if (content is List) {
      final parts = <String>[];
      for (final part in content) {
        if (part is String) {
          parts.add(part);
        } else if (part is Map) {
          final text = part['text'];
          if (text is String && text.trim().isNotEmpty) parts.add(text.trim());
        }
      }
      return parts.join('\n').trim();
    }
    return '';
  }

  /// Generate a response from the AI provider.
  /// Returns the assistant's message content.
  static Future<String> generate({
    required AiProvider provider,
    required String systemPrompt,
    required List<ChatMessage> messages,
  }) async {
    return _withRetry(() {
      if (provider.id == 'anthropic') {
        return _callAnthropic(provider, systemPrompt, messages);
      } else if (provider.id == 'openrouter') {
        return _callOpenRouter(provider, systemPrompt, messages);
      } else if (provider.id == 'openai_compatible') {
        return _callOpenAICompatible(provider, systemPrompt, messages);
      }
      throw Exception('Unknown provider: ${provider.id}');
    });
  }

  /// Retry on transient connection errors (reset by peer, timeout).
  static Future<String> _withRetry(Future<String> Function() call, {int maxRetries = 2}) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await call();
      } on SocketException catch (e) {
        if (attempt == maxRetries) rethrow;
        debugPrint('[AI] Connection error, retrying (${attempt + 1}/$maxRetries): $e');
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      } on HttpException catch (e) {
        if (attempt == maxRetries) rethrow;
        debugPrint('[AI] HTTP error, retrying (${attempt + 1}/$maxRetries): $e');
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    throw Exception('Request failed after $maxRetries retries');
  }

  /// Test the provider connection with a simple prompt.
  static Future<bool> testConnection(AiProvider provider) async {
    try {
      final result = await generate(
        provider: provider,
        systemPrompt: 'Respond with exactly: OK',
        messages: [ChatMessage(role: 'user', content: 'Test')],
      );
      return result.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Fetch available models from Anthropic.
  static Future<List<AiModel>> fetchAnthropicModels(String apiKey) async {
    final response = await http.get(
      Uri.parse('https://api.anthropic.com/v1/models?limit=1000'),
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) throw Exception('Failed to fetch models: ${response.statusCode}');

    final data = jsonDecode(response.body);
    final models = (data['data'] as List).map((m) {
      return AiModel(
        id: m['id'] as String,
        name: m['display_name'] as String? ?? m['id'] as String,
        contextLength: m['max_input_tokens'] as int?,
      );
    }).toList();

    // Sort: newest families first (opus > sonnet > haiku), then by id descending for version
    models.sort((a, b) {
      int family(AiModel m) {
        final id = m.id.toLowerCase();
        if (id.contains('opus')) return 0;
        if (id.contains('sonnet')) return 1;
        if (id.contains('haiku')) return 2;
        return 3;
      }
      final fc = family(a).compareTo(family(b));
      if (fc != 0) return fc;
      return b.id.compareTo(a.id); // newer versions first within same family
    });

    return models;
  }

  /// Fetch available models from OpenRouter (public endpoint, no key needed).
  static Future<List<AiModel>> fetchOpenRouterModels(String apiKey) async {
    final response = await http.get(
      Uri.parse('https://openrouter.ai/api/v1/models'),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) throw Exception('Failed to fetch models: ${response.statusCode}');

    final data = jsonDecode(response.body);
    final models = (data['data'] as List).map((m) {
      final pricing = m['pricing'] as Map?;
      final prompt = pricing != null ? double.tryParse(pricing['prompt']?.toString() ?? '') : null;
      return AiModel(
        id: m['id'] as String,
        name: m['name'] as String? ?? m['id'] as String,
        contextLength: m['context_length'] as int?,
        pricePer1mTokens: prompt != null ? prompt * 1000000 : null,
      );
    }).toList();

    // Sort: Claude first, then GPT, then others
    models.sort((a, b) {
      int score(AiModel m) {
        if (m.id.contains('claude')) return 0;
        if (m.id.contains('gpt')) return 1;
        if (m.id.contains('llama')) return 2;
        if (m.id.contains('mistral')) return 3;
        return 4;
      }
      return score(a).compareTo(score(b));
    });

    return models;
  }

  /// Fetch models from an OpenAI-compatible server (key optional).
  static Future<List<AiModel>> fetchOpenAICompatibleModels(String baseUrl, String apiKey) async {
    final headers = <String, String>{};
    if (apiKey.isNotEmpty) headers['Authorization'] = 'Bearer $apiKey';

    final response = await http.get(
      OpenAICompatible.modelsEndpoint(baseUrl),
      headers: headers,
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(OpenAICompatible.parseApiError(response.statusCode, response.body));
    }
    return OpenAICompatible.parseModels(response.body);
  }

  // ── Anthropic ──

  static Future<String> _callAnthropic(AiProvider provider, String systemPrompt, List<ChatMessage> messages) async {
    final body = jsonEncode({
      'model': provider.selectedModel,
      'max_tokens': 16000,
      // System prompt as a cached content block — Anthropic stores the tokenized
      // prefix server-side for 5 minutes. Repeat calls (edits, retries) within
      // that window skip re-processing the ~51KB bridge reference: ~90% cheaper
      // on input tokens, slightly faster.
      'system': [
        {
          'type': 'text',
          'text': systemPrompt,
          'cache_control': {'type': 'ephemeral'},
        }
      ],
      'messages': messages.map((m) => {'role': m.role, 'content': m.content}).toList(),
    });

    final response = await http.post(
      Uri.parse(provider.baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': provider.apiKey,
        'anthropic-version': '2023-06-01',
        'anthropic-beta': 'prompt-caching-2024-07-31',
      },
      body: body,
    ).timeout(const Duration(seconds: 300));

    if (response.statusCode != 200) {
      throw Exception(OpenAICompatible.parseApiError(
          response.statusCode, response.body));
    }

    final data = jsonDecode(response.body);
    if (isTruncatedFinishReason(data['stop_reason']?.toString())) {
      throw const AiTruncatedException(
          'The AI response was cut off at the output limit before the app was '
          'complete. Retry, or choose a model with a larger output limit.');
    }
    final content = data['content'];
    if (content is List) {
      final texts = <String>[];
      for (final block in content) {
        if (block is Map && block['type'] == 'text') {
          final text = block['text'];
          if (text is String && text.trim().isNotEmpty) texts.add(text.trim());
        }
      }
      if (texts.isNotEmpty) return texts.join('\n');
    }
    throw Exception('The AI returned no text content.');
  }

  // ── OpenRouter ──

  static Future<String> _callOpenRouter(AiProvider provider, String systemPrompt, List<ChatMessage> messages) async {
    final allMessages = [
      {'role': 'system', 'content': systemPrompt},
      ...messages.map((m) => {'role': m.role, 'content': m.content}),
    ];

    final body = jsonEncode({
      'model': provider.selectedModel,
      'max_tokens': 16000,
      'messages': allMessages,
    });

    final response = await http.post(
      Uri.parse(provider.baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${provider.apiKey}',
        'HTTP-Referer': 'https://github.com/Konprostart/Applix',
        'X-Title': 'Applix',
      },
      body: body,
    ).timeout(const Duration(seconds: 300));

    if (response.statusCode != 200) {
      throw Exception(OpenAICompatible.parseApiError(
          response.statusCode, response.body));
    }

    final data = jsonDecode(response.body);
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw Exception('Empty response from API');
    }
    final first = choices.first;
    if (first is! Map) throw Exception('Unexpected response from API');
    if (isTruncatedFinishReason(first['finish_reason']?.toString())) {
      throw const AiTruncatedException(
          'The AI response was cut off at the output limit before the app was '
          'complete. Retry, or choose a model with a larger output limit.');
    }
    final text = contentFromMessage(first['message']);
    if (text.isNotEmpty) return text;
    throw Exception('The AI returned no text content.');
  }

  // ── OpenAI-compatible (Ollama, LM Studio, vLLM, ...) ──

  static Future<String> _callOpenAICompatible(AiProvider provider, String systemPrompt, List<ChatMessage> messages) async {
    final allMessages = [
      {'role': 'system', 'content': systemPrompt},
      ...messages.map((m) => {'role': m.role, 'content': m.content}),
    ];

    final body = jsonEncode({
      'model': provider.selectedModel,
      'max_tokens': 16000,
      'messages': allMessages,
    });

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (provider.apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${provider.apiKey}';
    }

    final response = await http.post(
      OpenAICompatible.chatEndpoint(provider.baseUrl),
      headers: headers,
      body: body,
    ).timeout(const Duration(seconds: 300));

    if (response.statusCode != 200) {
      throw Exception(OpenAICompatible.parseApiError(response.statusCode, response.body));
    }
    final data = jsonDecode(response.body);
    final choices = data is Map ? data['choices'] : null;
    if (choices is! List || choices.isEmpty) {
      throw Exception('Empty response from API');
    }
    final first = choices.first;
    if (first is! Map) throw Exception('Unexpected response from API');
    if (isTruncatedFinishReason(first['finish_reason']?.toString())) {
      throw const AiTruncatedException(
          'The AI response was cut off at the output limit before the app was '
          'complete. Retry, or choose a model with a larger output limit.');
    }
    final text = contentFromMessage(first['message']);
    if (text.isNotEmpty) return text;
    throw Exception('The AI returned no text content.');
  }
}
