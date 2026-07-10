import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/db.dart';
import '../../data/repo.dart';
import '../../domain/l10n.dart';
import '../../services/asset_service.dart';
import '../../theme/tokens.dart';
import 'audio_player_widget.dart';

/// Timed single-task mock (spec §7): task PDF opens alongside, audio (if
/// paired) plays inline, answers auto-graded against the hand-entered key.
class MockRunScreen extends StatefulWidget {
  final Repo repo;
  final AssetService assets;
  final RadaTokens tokens;
  final L10n l;
  final ExamAsset taskAsset;
  final ExamAsset? audioAsset;
  final List<String> answerKey;

  const MockRunScreen({
    super.key,
    required this.repo,
    required this.assets,
    required this.tokens,
    required this.l,
    required this.taskAsset,
    required this.audioAsset,
    required this.answerKey,
  });

  @override
  State<MockRunScreen> createState() => _MockRunScreenState();
}

class _MockRunScreenState extends State<MockRunScreen> {
  late final List<TextEditingController> _answers = List.generate(
      widget.answerKey.length, (_) => TextEditingController());
  late final int _limitS =
      widget.taskAsset.section == 'kuulamine' ? 15 * 60 : 20 * 60;
  final _watch = Stopwatch()..start();
  Timer? _ticker;
  String? _audioPath;
  double? _resultPct;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
      if (_watch.elapsed.inSeconds >= _limitS && _resultPct == null) {
        _submit();
      }
    });
    _prepareAudio();
  }

  Future<void> _prepareAudio() async {
    final audio = widget.audioAsset;
    if (audio == null) return;
    final path = await widget.assets.ensureDownloaded(audio);
    if (mounted) setState(() => _audioPath = path);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final c in _answers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _openTaskPdf() async {
    if (Platform.isAndroid) {
      await launchUrl(Uri.parse(widget.taskAsset.remoteUrl),
          mode: LaunchMode.externalApplication);
    } else {
      final path = await widget.assets.ensureDownloaded(widget.taskAsset);
      await launchUrl(Uri.file(path));
    }
  }

  String _norm(String s) => s.trim().toLowerCase().replaceAll(',', '.');

  Future<void> _submit() async {
    _watch.stop();
    _ticker?.cancel();
    var correct = 0;
    final given = _answers.map((c) => c.text).toList();
    for (var i = 0; i < widget.answerKey.length; i++) {
      if (_norm(given[i]) == _norm(widget.answerKey[i])) correct++;
    }
    final pct = 100.0 * correct / widget.answerKey.length;
    await widget.repo.saveMockResult(
      section: widget.taskAsset.section,
      assetId: widget.taskAsset.id,
      given: given,
      correct: widget.answerKey,
      pct: pct,
      durationS: _watch.elapsed.inSeconds,
    );
    if (mounted) setState(() => _resultPct = pct);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final l = widget.l;
    final left = _limitS - _watch.elapsed.inSeconds;
    final mm = (left ~/ 60).toString().padLeft(2, '0');
    final ss = (left % 60).toString().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.taskAsset.title),
        actions: [
          if (_resultPct == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('$mm:$ss',
                    style: TextStyle(
                        color: left < 60 ? t.warning : t.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_resultPct != null) _resultCard(t, l),
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.picture_as_pdf),
                label: Text(l.t('Open task PDF', 'Ava ülesande PDF')),
                onPressed: _openTaskPdf,
              ),
            ],
          ),
          if (widget.audioAsset != null) ...[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _audioPath == null
                    ? const LinearProgressIndicator()
                    : AudioPlayerWidget(
                        filePath: _audioPath!,
                        title: widget.audioAsset!.title),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(l.t('Answers', 'Vastused'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (var i = 0; i < _answers.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: TextField(
                controller: _answers[i],
                enabled: _resultPct == null,
                decoration: InputDecoration(
                  labelText: '${i + 1}',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (_resultPct == null)
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: Text(l.t('Submit', 'Esita')),
              onPressed: _submit,
            ),
        ],
      ),
    );
  }

  Widget _resultCard(RadaTokens t, L10n l) {
    final pct = _resultPct!;
    final color = pct >= 60 ? t.success : (pct >= 45 ? t.warning : Colors.red);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${pct.toStringAsFixed(0)}%',
                style: Theme.of(context)
                    .textTheme
                    .displaySmall
                    ?.copyWith(color: color, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(pct >= 60
                ? l.t('Above the 60% pass line', 'Üle 60% lävendi')
                : pct >= 45
                    ? l.t('Below pass (60%), above retake lockout (45%)',
                        'Alla lävendi (60%), üle 45%')
                    : l.t('Below 45% — on the real exam this triggers a 6-month retake lockout',
                        'Alla 45% — päris eksamil 6-kuuline ootekord')),
            const SizedBox(height: 8),
            for (var i = 0; i < widget.answerKey.length; i++)
              if (_norm(_answers[i].text) != _norm(widget.answerKey[i]))
                Text(
                    '${i + 1}: ${_answers[i].text.isEmpty ? "—" : _answers[i].text} → ${widget.answerKey[i]}',
                    style: TextStyle(color: t.textSecondary)),
          ],
        ),
      ),
    );
  }
}
