import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/db.dart';
import '../../data/repo.dart';
import '../../domain/l10n.dart';
import '../../services/asset_service.dart';
import '../../theme/tokens.dart';
import 'audio_player_widget.dart';
import 'mock_run_screen.dart';

/// Exam vault (spec §7): official materials, answer keys, mocks, history.
class VaultScreen extends StatefulWidget {
  final Repo repo;
  final RadaTokens tokens;
  final L10n l;
  const VaultScreen(
      {super.key, required this.repo, required this.tokens, required this.l});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  late final AssetService _assets = AssetService(widget.repo.db);
  List<ExamAsset> _items = [];
  Map<String, List<String>> _keys = {};
  List<MockExam> _history = [];
  final Set<String> _busy = {};

  static const _sections = [
    ('kuulamine', 'Listening', 'Kuulamine'),
    ('lugemine', 'Reading', 'Lugemine'),
    ('kirjutamine', 'Writing', 'Kirjutamine'),
    ('raakimine', 'Speaking', 'Rääkimine'),
    ('general', 'General', 'Üldine'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.repo.examAssets();
    final history = await widget.repo.mockHistory();
    final keys = <String, List<String>>{};
    for (final a in items) {
      final k = await widget.repo.answerKeyFor(a.id);
      if (k != null) keys[a.id] = k;
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _keys = keys;
      _history = history;
    });
  }

  String _group(String title) => title.split('·').first.trim();

  ExamAsset? _audioFor(ExamAsset task) {
    final g = _group(task.title);
    for (final a in _items) {
      if (a.kind == 'mp3' && _group(a.title) == g && a.id != task.id) {
        return a;
      }
    }
    return null;
  }

  Future<void> _open(ExamAsset a) async {
    setState(() => _busy.add(a.id));
    try {
      if (a.kind == 'mp3') {
        final path = await _assets.ensureDownloaded(a);
        if (!mounted) return;
        await showModalBottomSheet(
          context: context,
          builder: (_) => Padding(
            padding: const EdgeInsets.all(16),
            child: AudioPlayerWidget(filePath: path, title: a.title),
          ),
        );
      } else if (Platform.isAndroid) {
        await launchUrl(Uri.parse(a.remoteUrl),
            mode: LaunchMode.externalApplication);
      } else {
        final path = await _assets.ensureDownloaded(a);
        await launchUrl(Uri.file(path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(a.id));
    }
    _load();
  }

  Future<void> _editKey(ExamAsset a) async {
    final existing = _keys[a.id]?.join(', ') ?? '';
    final ctl = TextEditingController(text: existing);
    final l = widget.l;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.t('Answer key', 'Vastuste võti')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.t(
                  'From the official PDF: enter correct answers in order, comma-separated (e.g. B, A, C, 15.30)',
                  'Ametlikust PDF-ist: õiged vastused järjekorras, komadega (nt B, A, C, 15.30)'),
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctl,
              maxLines: 3,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.t('Cancel', 'Loobu')),
          ),
          FilledButton(
            onPressed: () async {
              final answers = ctl.text
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              if (answers.isNotEmpty) {
                await widget.repo.saveAnswerKey(a.id, answers);
              }
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            },
            child: Text(l.short('Save', 'Salvesta')),
          ),
        ],
      ),
    );
  }

  Future<void> _startMock(ExamAsset a) async {
    final key = _keys[a.id];
    if (key == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MockRunScreen(
        repo: widget.repo,
        assets: _assets,
        tokens: widget.tokens,
        l: widget.l,
        taskAsset: a,
        audioAsset: _audioFor(a),
        answerKey: key,
      ),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.t('Exam vault', 'Eksami varamu')),
          bottom: TabBar(tabs: [
            Tab(text: l.t('Materials & mocks', 'Materjalid ja proovid')),
            Tab(text: l.t('History', 'Ajalugu')),
          ]),
        ),
        body: TabBarView(children: [
          _materialsTab(l),
          _historyTab(l),
        ]),
      ),
    );
  }

  Widget _materialsTab(L10n l) {
    final t = widget.tokens;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final (slug, en, et) in _sections) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(l.t(en, et),
                style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final a in _items.where((a) => a.section == slug))
            Card(
              margin: const EdgeInsets.symmetric(vertical: 3),
              child: ListTile(
                dense: true,
                leading: Icon(
                  a.kind == 'mp3' ? Icons.headphones : Icons.picture_as_pdf,
                  color: a.localPath != null ? t.accent : t.textSecondary,
                ),
                title: Text(a.title),
                subtitle: a.localPath != null
                    ? Text(l.t('downloaded', 'alla laaditud'),
                        style: TextStyle(color: t.success, fontSize: 12))
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_busy.contains(a.id))
                      const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    if (a.kind == 'pdf' &&
                        (a.section == 'kuulamine' || a.section == 'lugemine'))
                      IconButton(
                        tooltip: l.t('Answer key', 'Vastuste võti'),
                        icon: Icon(
                          Icons.key,
                          size: 18,
                          color: _keys.containsKey(a.id)
                              ? t.accent
                              : t.textSecondary,
                        ),
                        onPressed: () => _editKey(a),
                      ),
                    if (_keys.containsKey(a.id))
                      IconButton(
                        tooltip: l.t('Start mock', 'Alusta proovi'),
                        icon: Icon(Icons.timer, size: 18, color: t.accentAlt),
                        onPressed: () => _startMock(a),
                      ),
                  ],
                ),
                onTap: () => _open(a),
              ),
            ),
        ],
      ],
    );
  }

  Widget _historyTab(L10n l) {
    final t = widget.tokens;
    if (_history.isEmpty) {
      return Center(
          child: Text(l.t('No mock results yet', 'Proovitulemusi pole veel')));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final m in _history)
          Builder(builder: (_) {
            final pct = m.totalPct ?? 0;
            final data = jsonDecode(m.sectionsJson) as Map<String, dynamic>;
            final color =
                pct >= 60 ? t.success : (pct >= 45 ? t.warning : Colors.red);
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 3),
              child: ListTile(
                dense: true,
                leading: Text('${pct.toStringAsFixed(0)}%',
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                title: Text('${data['section']}'),
                subtitle: Text(
                    '${m.startedAt.toString().substring(0, 16)} · '
                    '${((data['duration_s'] ?? 0) / 60).round()} min'),
                trailing: SizedBox(
                  width: 100,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct / 100,
                      minHeight: 8,
                      color: color,
                      backgroundColor: t.surfaceAlt,
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}
