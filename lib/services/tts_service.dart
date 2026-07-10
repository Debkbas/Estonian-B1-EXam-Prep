import 'dart:io';
import 'package:crypto/crypto.dart' show sha256;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Spec §6.1 — Neurokõne (TartuNLP) TTS with disk cache.
abstract class TtsService {
  /// Returns a local file path to synthesized audio for [text].
  Future<String> synthesize(String text, {String voice, double speed});
}

/// M0-level implementation: cache-or-fetch against the public TartuNLP API.
/// NOTE (M3): verify current endpoint/params against
/// https://github.com/TartuNLP/text-to-speech-api before relying on this.
class NeurokoneTts implements TtsService {
  static const _endpoint = 'https://api.tartunlp.ai/text-to-speech/v2';

  @override
  Future<String> synthesize(String text,
      {String voice = 'mari', double speed = 1.0}) async {
    final key = sha256.convert(utf8.encode('$voice|$speed|$text')).toString();
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/tts_cache/$key.wav');
    if (await file.exists()) return file.path;

    final resp = await http.post(
      Uri.parse(_endpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text, 'speaker': voice, 'speed': speed}),
    );
    if (resp.statusCode != 200) {
      throw TtsException('Neurokõne HTTP ${resp.statusCode}');
    }
    await file.create(recursive: true);
    await file.writeAsBytes(resp.bodyBytes);
    return file.path;
  }
}

class TtsException implements Exception {
  final String message;
  TtsException(this.message);
  @override
  String toString() => 'TtsException: $message';
}
