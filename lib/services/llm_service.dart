import 'dart:convert';
import 'package:http/http.dart' as http;

/// Spec §6.4 — hybrid LLM. One interface, two adapters, switchable per
/// feature in settings. M0 ships the OpenAI-compatible adapter skeleton
/// (works against LM Studio); the Anthropic adapter lands in M3.
abstract class LlmService {
  String get backendLabel; // 'local' | 'cloud'
  Future<String> complete({required String system, required String user});
}

/// Works against any OpenAI-compatible endpoint, e.g. LM Studio at
/// http://127.0.0.1:1234/v1 (spec §3).
class OpenAiCompatibleLlm implements LlmService {
  final String baseUrl;
  final String model;
  final String? apiKey;

  OpenAiCompatibleLlm({
    required this.baseUrl,
    this.model = 'local-model',
    this.apiKey,
  });

  @override
  String get backendLabel => 'local';

  @override
  Future<String> complete({required String system, required String user}) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        if (apiKey != null) 'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': user},
        ],
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('LLM HTTP ${resp.statusCode}: ${resp.body}');
    }
    final json = jsonDecode(utf8.decode(resp.bodyBytes));
    return json['choices'][0]['message']['content'] as String;
  }
}
