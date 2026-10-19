import 'dart:convert';

import '../models/ai_provider.dart';

/// Helpers for OpenAI-compatible endpoints (Ollama, LM Studio, vLLM, ...).
class OpenAICompatible {
  static String _normalize(String baseUrl) {
    var url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.isEmpty) throw const FormatException('Base URL is empty');
    return url;
  }

  /// Accepts a server root, a `/v1` base or a full chat completions URL.
  static Uri chatEndpoint(String baseUrl) {
    final url = _normalize(baseUrl);
    if (url.endsWith('/chat/completions')) return Uri.parse(url);
    if (url.endsWith('/v1')) return Uri.parse('$url/chat/completions');
    return Uri.parse('$url/v1/chat/completions');
  }

  /// Accepts a server root, a `/v1` base or a full chat completions URL.
  static Uri modelsEndpoint(String baseUrl) {
    var url = _normalize(baseUrl);
    if (url.endsWith('/chat/completions')) {
      url = url.substring(0, url.length - '/chat/completions'.length);
    }
    if (url.endsWith('/v1')) return Uri.parse('$url/models');
    return Uri.parse('$url/v1/models');
  }

  static List<AiModel> parseModels(String body) {
    final decoded = jsonDecode(body);
    final list = decoded is Map ? decoded['data'] : decoded;
    if (list is! List) throw const FormatException('Unexpected models response');

    final models = <AiModel>[];
    for (final item in list) {
      if (item is! Map) continue;
      final id = (item['id'] ?? item['name'])?.toString() ?? '';
      if (id.isEmpty) continue;
      final context = item['context_length'];
      models.add(AiModel(
        id: id,
        name: (item['name'] ?? id).toString(),
        contextLength: context is num ? context.toInt() : null,
      ));
    }
    models.sort((a, b) => a.id.toLowerCase().compareTo(b.id.toLowerCase()));
    return models;
  }

  static String parseCompletion(String body) {
    final decoded = jsonDecode(body);
    final choices = decoded is Map ? decoded['choices'] : null;
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('Empty response from API');
    }
    final first = choices.first;
    final message = first is Map ? first['message'] : null;
    final content = message is Map ? message['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('Empty response from API');
    }
    return content;
  }

  static String parseApiError(int status, String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] != null) return error['message'].toString();
        if (error is String && error.isNotEmpty) return error;
        if (decoded['message'] != null) return decoded['message'].toString();
      }
    } catch (_) {
      // Not JSON — fall through to the raw snippet.
    }
    final snippet = body.trim();
    if (snippet.isEmpty) return 'API error $status';
    final short = snippet.length > 200 ? '${snippet.substring(0, 200)}…' : snippet;
    return 'API error $status: $short';
  }
}
