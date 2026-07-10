import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../data/repo.dart';
import '../../domain/align.dart';
import '../../domain/drill_sentences.dart';
import '../../domain/l10n.dart';
import '../../theme/tokens.dart';
import 'speech_config.dart';

/// Pronunciation drill (spec §6.3): listen → speak → word-level feedback.
class PronounceTab extends StatefulWidget {
  final Repo repo;
  final RadaTokens tokens;
  final L10n l;
  final SpeechConfig config;
  final Speaker speaker;

  const PronounceTab({
    super.key,
    required this.repo,
    required this.tokens,
    required this.l,
    required this.config,
    required this.speaker,
  });

  @override
  State<PronounceTab> createState() => _PronounceTabState();
}

class _PronounceTabState extends State<PronounceTab> {
  final _rec = AudioRecorder();
  int _index = Random().nextInt(drillSentences.length);
  bool _recording = false;
  bool _busy = false;
  String? _heard;
  List<bool>? _matched;
  String? _error;

  @override
  void dispose() {
    _rec.dispose();
    super.dispose();
  }

  (String, String) get _current => drillSentences[_index];

  Future<void> _listen() async {
    setState(() => _error = null);
    try {
      await widget.speaker
          .speak(_current.$1, voice: widget.config.ttsVoice);
    } catch (e) {
      setState(() => _error = 'TTS: $e');
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
        final target = normalizeWords(_current.$1);
        final matched = alignWords(target, normalizeWords(transcript));
        final score =
            matched.where((m) => m).length / max(target.length, 1) * 100;
        await widget.repo.logActivity(1, 'speech',
            detail: {'mode': 'pronounce', 'score': score});
        setState(() {
          _heard = transcript;
          _matched = matched;
          _busy = false;
        });
      } catch (e) {
        setState(() {
          _error = '$e';
          _busy = false;
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
          path: '${dir.path}/drill.wav');
      setState(() {
        _recording = true;
        _heard = null;
        _matched = null;
        _error = null;
      });
    }
  }

  void _next() {
    setState(() {
      _index = (_index + 1) % drillSentences.length;
      _heard = null;
      _matched = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final l = widget.l;
    final (et, en) = _current;
    final targetWords = et.split(RegExp(r'\s+'));
    final normTarget = normalizeWords(et);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // target sentence, word-colored after an attempt
                Wrap(
                  spacing: 6,
                  children: [
                    for (var i = 0; i < targetWords.length; i++)
                      Text(
                        targetWords[i],
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: _matched == null || i >= normTarget.length
                              ? t.textPrimary
                              : (_matched![i] ? t.success : Colors.red),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(en, style: TextStyle(color: t.textSecondary)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.volume_up),
                      label: Text(l.t('Listen', 'Kuula')),
                      onPressed: _listen,
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      icon: Icon(_recording ? Icons.stop : Icons.mic),
                      label: Text(_recording
                          ? l.t('Stop', 'Stopp')
                          : l.t('Speak', 'Räägi')),
                      style: _recording
                          ? FilledButton.styleFrom(backgroundColor: Colors.red)
                          : null,
                      onPressed: _busy ? null : _toggleRecord,
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                        onPressed: _next,
                        child: Text(l.t('Next', 'Järgmine'))),
                  ],
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
        if (_heard != null)
          Card(
            child: ListTile(
              leading: Icon(Icons.hearing, color: t.accent),
              title: Text(_heard!.isEmpty
                  ? l.t('(nothing recognized)', '(midagi ei tuvastatud)')
                  : _heard!),
              subtitle: Text(l.t('What the Estonian ASR heard',
                  'Mida eesti keele tuvastus kuulis')),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 8),
        Text(
          l.t(
              'Requires the local Whisper server (see speech settings ⚙). Scores measure whether a good Estonian ASR understands you — a proxy for exam intelligibility.',
              'Vajab kohalikku Whisperi serverit (vt kõneseadeid ⚙).'),
          style: TextStyle(color: t.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}
