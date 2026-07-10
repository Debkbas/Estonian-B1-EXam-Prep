import 'package:just_audio/just_audio.dart';

import '../../data/repo.dart';
import '../../services/llm_service.dart';
import '../../services/stt_service.dart';
import '../../services/tts_service.dart';

/// Speech studio configuration (spec §6), persisted in settings_kv.
class SpeechConfig {
  String sttUrl;
  String llmMode; // 'local' | 'cloud'
  String lmstudioUrl;
  String lmstudioModel;
  String anthropicKey;
  String anthropicModel;
  String ttsVoice;

  SpeechConfig({
    required this.sttUrl,
    required this.llmMode,
    required this.lmstudioUrl,
    required this.lmstudioModel,
    required this.anthropicKey,
    required this.anthropicModel,
    required this.ttsVoice,
  });

  static Future<SpeechConfig> load(Repo repo) async => SpeechConfig(
        sttUrl: await repo.getSetting('stt_url') ?? 'http://127.0.0.1:8090',
        llmMode: await repo.getSetting('llm_mode') ?? 'cloud',
        lmstudioUrl: await repo.getSetting('lmstudio_url') ??
            'http://127.0.0.1:1234/v1',
        lmstudioModel:
            await repo.getSetting('lmstudio_model') ?? 'local-model',
        anthropicKey: await repo.getSetting('anthropic_key') ?? '',
        anthropicModel:
            await repo.getSetting('anthropic_model') ?? 'claude-sonnet-4-5',
        ttsVoice: await repo.getSetting('tts_voice') ?? 'mari',
      );

  Future<void> save(Repo repo) async {
    await repo.setSetting('stt_url', sttUrl);
    await repo.setSetting('llm_mode', llmMode);
    await repo.setSetting('lmstudio_url', lmstudioUrl);
    await repo.setSetting('lmstudio_model', lmstudioModel);
    await repo.setSetting('anthropic_key', anthropicKey);
    await repo.setSetting('anthropic_model', anthropicModel);
    await repo.setSetting('tts_voice', ttsVoice);
  }

  SttService get stt => WhisperServerStt(sttUrl);

  LlmService get llm => llmMode == 'cloud' && anthropicKey.isNotEmpty
      ? AnthropicLlm(apiKey: anthropicKey, model: anthropicModel)
      : OpenAiCompatibleLlm(baseUrl: lmstudioUrl, model: lmstudioModel);
}

/// TTS synthesize + play helper with the shared disk cache.
class Speaker {
  final TtsService tts = NeurokoneTts();
  final AudioPlayer _player = AudioPlayer();

  Future<void> speak(String text, {String voice = 'mari'}) async {
    final path = await tts.synthesize(text, voice: voice);
    await _player.setFilePath(path);
    await _player.play();
  }

  void dispose() => _player.dispose();
}
