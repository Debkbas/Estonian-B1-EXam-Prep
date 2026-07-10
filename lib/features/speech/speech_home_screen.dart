import 'package:flutter/material.dart';

import '../../data/repo.dart';
import '../../domain/l10n.dart';
import '../../theme/tokens.dart';
import 'converse_tab.dart';
import 'pronounce_tab.dart';
import 'speech_config.dart';
import 'write_tab.dart';

/// Speech studio hub (spec §6): pronunciation, conversation, writing.
class SpeechHomeScreen extends StatefulWidget {
  final Repo repo;
  final RadaTokens tokens;
  final L10n l;
  const SpeechHomeScreen(
      {super.key, required this.repo, required this.tokens, required this.l});

  @override
  State<SpeechHomeScreen> createState() => _SpeechHomeScreenState();
}

class _SpeechHomeScreenState extends State<SpeechHomeScreen> {
  SpeechConfig? _config;
  final Speaker _speaker = Speaker();

  @override
  void initState() {
    super.initState();
    SpeechConfig.load(widget.repo).then((c) {
      if (mounted) setState(() => _config = c);
    });
  }

  @override
  void dispose() {
    _speaker.dispose();
    super.dispose();
  }

  Future<void> _openConfig() async {
    final c = _config!;
    final l = widget.l;
    final sttCtl = TextEditingController(text: c.sttUrl);
    final lmUrlCtl = TextEditingController(text: c.lmstudioUrl);
    final lmModelCtl = TextEditingController(text: c.lmstudioModel);
    final keyCtl = TextEditingController(text: c.anthropicKey);
    var mode = c.llmMode;
    var voice = c.ttsVoice;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(l.t('Speech settings', 'Kõne seaded')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.t('Corrections brain', 'Paranduste mootor'),
                      style: Theme.of(ctx).textTheme.titleSmall),
                  Wrap(spacing: 8, children: [
                    ChoiceChip(
                      label: const Text('Claude (cloud)'),
                      selected: mode == 'cloud',
                      onSelected: (_) => setD(() => mode = 'cloud'),
                    ),
                    ChoiceChip(
                      label: const Text('LM Studio (local)'),
                      selected: mode == 'local',
                      onSelected: (_) => setD(() => mode = 'local'),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  if (mode == 'cloud')
                    TextField(
                      controller: keyCtl,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Anthropic API key',
                          border: OutlineInputBorder(),
                          isDense: true),
                    )
                  else ...[
                    TextField(
                      controller: lmUrlCtl,
                      decoration: const InputDecoration(
                          labelText: 'LM Studio URL',
                          border: OutlineInputBorder(),
                          isDense: true),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: lmModelCtl,
                      decoration: const InputDecoration(
                          labelText: 'Model',
                          border: OutlineInputBorder(),
                          isDense: true),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: sttCtl,
                    decoration: InputDecoration(
                        labelText: l.t('Whisper server URL (STT)',
                            'Whisperi serveri URL'),
                        helperText: 'whisper-server -m whisper-large-et.ggml '
                            '--port 8090 --language et',
                        border: const OutlineInputBorder(),
                        isDense: true),
                  ),
                  const SizedBox(height: 12),
                  Text(l.t('Voice (Neurokõne)', 'Hääl (Neurokõne)'),
                      style: Theme.of(ctx).textTheme.titleSmall),
                  Wrap(spacing: 6, children: [
                    for (final v in ['mari', 'tambet', 'liivika', 'kalev'])
                      ChoiceChip(
                        label: Text(v),
                        selected: voice == v,
                        onSelected: (_) => setD(() => voice = v),
                      ),
                  ]),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l.t('Cancel', 'Loobu'))),
            FilledButton(
              onPressed: () async {
                c
                  ..sttUrl = sttCtl.text.trim()
                  ..llmMode = mode
                  ..lmstudioUrl = lmUrlCtl.text.trim()
                  ..lmstudioModel = lmModelCtl.text.trim()
                  ..anthropicKey = keyCtl.text.trim()
                  ..ttsVoice = voice;
                await c.save(widget.repo);
                if (ctx.mounted) Navigator.pop(ctx);
                setState(() {});
              },
              child: Text(l.short('Save', 'Salvesta')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final config = _config;
    if (config == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.t('Speech studio', 'Kõnestuudio')),
          actions: [
            IconButton(
              tooltip: l.t('Speech settings', 'Kõne seaded'),
              icon: const Icon(Icons.settings_voice),
              onPressed: _openConfig,
            ),
          ],
          bottom: TabBar(tabs: [
            Tab(text: l.t('Pronounce', 'Hääldus')),
            Tab(text: l.t('Converse', 'Vestlus')),
            Tab(text: l.t('Write', 'Kirjutamine')),
          ]),
        ),
        body: TabBarView(children: [
          PronounceTab(
              repo: widget.repo,
              tokens: widget.tokens,
              l: l,
              config: config,
              speaker: _speaker),
          ConverseTab(
              repo: widget.repo,
              tokens: widget.tokens,
              l: l,
              config: config,
              speaker: _speaker),
          WriteTab(
              repo: widget.repo, tokens: widget.tokens, l: l, config: config),
        ]),
      ),
    );
  }
}
