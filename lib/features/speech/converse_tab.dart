import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../data/repo.dart';
import '../../domain/l10n.dart';
import '../../services/llm_service.dart';
import '../../theme/tokens.dart';
import 'speech_config.dart';

const _tutorSystem = '''
You are an Estonian language tutor for a B1-exam candidate (English native).
Rules:
- Reply in simple, natural Estonian at A2–B1 level, 1-3 sentences, then keep
  the conversation going with a question.
- If the student's Estonian contains errors, append a line "---" and after it
  list corrections in English: original → corrected (one short reason each).
  If there were no errors, append "--- ✓".
- Stay on everyday exam topics: home, work, shopping, health, travel, plans.
''';

/// Conversation practice (spec §6.4): speak or type → tutor replies in
/// Estonian (spoken via TTS) + English corrections.
class ConverseTab extends StatefulWidget {
  final Repo repo;
  final RadaTokens tokens;
  final L10n l;
  final SpeechConfig config;
  final Speaker speaker;

  const ConverseTab({
    super.key,
    required this.repo,
    required this.tokens,
    required this.l,
    required this.config,
    required this.speaker,
  });

  @override
  State<ConverseTab> createState() => _ConverseTabState();
}

class _ConverseTabState extends State<ConverseTab> {
  final _rec = AudioRecorder();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMsg> _history = [];
  bool _recording = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _rec.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _history.add(ChatMsg('user', text.trim()));
      _busy = true;
      _error = null;
      _input.clear();
    });
    try {
      final reply = await widget.config.llm
          .chat(system: _tutorSystem, messages: List.of(_history));
      setState(() {
        _history.add(ChatMsg('assistant', reply));
        _busy = false;
      });
      await widget.repo.logActivity(1, 'speech',
          detail: {'mode': 'converse', 'backend': widget.config.llm.backendLabel});
      // speak only the Estonian part (before ---)
      final spoken = reply.split('---').first.trim();
      if (spoken.isNotEmpty) {
        try {
          await widget.speaker.speak(spoken, voice: widget.config.ttsVoice);
        } catch (_) {} // TTS failure shouldn't kill the chat
      }
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      final path = await _rec.stop();
      setState(() {
        _recording = false;
        _busy = true;
      });
      if (path == null) {
        setState(() => _busy = false);
        return;
      }
      try {
        final transcript = await widget.config.stt.transcribe(path);
        setState(() => _busy = false);
        if (transcript.isNotEmpty) await _send(transcript);
      } catch (e) {
        setState(() {
          _busy = false;
          _error = 'STT: $e';
        });
      }
    } else {
      if (!await _rec.hasPermission()) {
        setState(() => _error = widget.l
            .t('Microphone permission denied', 'Mikrofoni luba puudub'));
        return;
      }
      final dir = await getApplicationSupportDirectory();
      await _rec.start(const RecordConfig(encoder: AudioEncoder.wav),
          path: '${dir.path}/converse.wav');
      setState(() => _recording = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final l = widget.l;
    final isCloud = widget.config.llm.backendLabel == 'cloud';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Icon(isCloud ? Icons.cloud_outlined : Icons.computer,
                  size: 14, color: t.textSecondary),
              const SizedBox(width: 4),
              Text(
                isCloud
                    ? 'Claude'
                    : l.t('local LLM — corrections unverified',
                        'kohalik LLM — parandused kontrollimata'),
                style: TextStyle(color: t.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            children: [
              if (_history.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l.t(
                        'Say tere and start a conversation — speak with the mic or type below. The tutor answers in Estonian and corrects you in English.',
                        'Ütle tere ja alusta vestlust!'),
                    style: TextStyle(color: t.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final m in _history) _bubble(t, m),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: LinearProgressIndicator(),
                ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: [
                IconButton.filled(
                  icon: Icon(_recording ? Icons.stop : Icons.mic),
                  style: _recording
                      ? IconButton.styleFrom(backgroundColor: Colors.red)
                      : null,
                  onPressed: _busy ? null : _toggleRecord,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: InputDecoration(
                      hintText: l.t('…or type in Estonian', '…või kirjuta'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: _busy ? null : _send,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _busy ? null : () => _send(_input.text),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bubble(RadaTokens t, ChatMsg m) {
    final isUser = m.role == 'user';
    final parts = m.content.split('---');
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: isUser ? t.accent.withValues(alpha: 0.15) : t.surfaceAlt,
          borderRadius: BorderRadius.circular(t.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(parts.first.trim()),
            if (!isUser && parts.length > 1 && parts[1].trim() != '✓') ...[
              const Divider(),
              Text(parts.sublist(1).join('---').trim(),
                  style: TextStyle(color: t.textSecondary, fontSize: 13)),
            ],
            if (!isUser && parts.length > 1 && parts[1].trim() == '✓')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(Icons.check_circle, size: 16, color: t.success),
              ),
          ],
        ),
      ),
    );
  }
}
