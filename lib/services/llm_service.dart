import 'dart:convert';

import 'package:http/http.dart' as http;

/// Spec §6.4 — hybrid LLM. One interface, two adapters, switchable in
/// speech settings. Cloud (Claude) is the default for corrections/grading;
/// local (LM Studio) is available for conversation flow and offline use,
/// with local corrections treated as unverified.
class ChatMsg {
  final String role; // 'user' | 'assistant'
  final String content;
  const ChatMsg(this.role, this.content);
}

abstract class LlmService {
  String get backendLabel; // 'local' | 'cloud'
  Future<String> chat(
      {required String system, required List<ChatMsg> messages});
}

/// Any OpenAI-compatible endpoint, e.g. LM Studio at http://127.0.0.1:1234/v1
class OpenAiCompatibleLlm implements LlmService {
  final String baseUrl;
  final String model;
  final String? apiKey;

  OpenAiCompatibleLlm(
      {required this.baseUrl, this.model = 'local-model', this.apiKey});

  @override
  String get backendLabel => 'local';

  @override
  Future<String> chat(
      {required String system, required List<ChatMsg> messages}) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            if (apiKey != null) 'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'system', 'content': system},
              for (final m in messages)
                {'role': m.role, 'content': m.content},
            ],
          }),
        )
        .timeout(const Duration(minutes: 3));
    if (resp.statusCode != 200) {
      throw Exception('LLM HTTP ${resp.statusCode}: ${resp.body}');
    }
    final json = jsonDecode(utf8.decode(resp.bodyBytes));
    return json['choices'][0]['message']['content'] as String;
  }
}

/// Anthropic Messages API (cloud mode).
class AnthropicLlm implements LlmService {
  final String apiKey;
  final String model;

  AnthropicLlm({required this.apiKey, this.model = 'claude-sonnet-4-5'});

  @override
  String get backendLabel => 'cloud';

  @override
  Future<String> chat(
      {required String system, required List<ChatMsg> messages}) async {
    final resp = await http
        .post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode({
            'model': model,
            'max_tokens': 1024,
            'system': system,
            'messages': [
              for (final m in messages)
                {'role': m.role, 'content': m.content},
            ],
          }),
        )
        .timeout(const Duration(minutes: 2));
    if (resp.statusCode != 200) {
      throw Exception('Anthropic HTTP ${resp.statusCode}: ${resp.body}');
    }
    final json = jsonDecode(utf8.decode(resp.bodyBytes));
    return json['content'][0]['text'] as String;
  }
}
