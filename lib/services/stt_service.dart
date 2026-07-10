import 'dart:convert';

import 'package:http/http.dart' as http;

/// Spec §6.2 — STT. M3 implementation: whisper.cpp's built-in HTTP server
/// running locally with the Estonian model (TalTechNLP/whisper-large-et
/// converted to GGML). Start it on the Mac with e.g.:
///
///   whisper-server -m whisper-large-et.ggml --port 8090 --language et
///
/// The app POSTs the recording and reads back the transcript. Same
/// local-server pattern as LM Studio — no fragile native plugin.
abstract class SttService {
  Future<String> transcribe(String audioFilePath);
}

class WhisperServerStt implements SttService {
  final String baseUrl; // e.g. http://127.0.0.1:8090
  WhisperServerStt(this.baseUrl);

  @override
  Future<String> transcribe(String audioFilePath) async {
    final uri = Uri.parse('$baseUrl/inference');
    final req = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('file', audioFilePath))
      ..fields['language'] = 'et'
      ..fields['response_format'] = 'json';
    final streamed = await req.send().timeout(const Duration(minutes: 3));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw SttException('Whisper server HTTP ${streamed.statusCode}: $body');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    return (json['text'] as String? ?? '').trim();
  }
}

class SttException implements Exception {
  final String message;
  SttException(this.message);
  @override
  String toString() => 'SttException: $message';
}
