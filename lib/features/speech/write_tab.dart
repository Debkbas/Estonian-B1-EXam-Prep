import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/repo.dart';
import '../../domain/l10n.dart';
import '../../services/llm_service.dart';
import '../../theme/tokens.dart';
import 'speech_config.dart';

const _writeSystem = '''
You grade Estonian B1 exam writing (isiklik kiri / short message).
Grade against the official B1 criteria: task completion, vocabulary range,
grammar accuracy, coherence. The expected length is 80-120 words.
Answer in English with this structure:
SCORE: n/25
STRENGTHS: 1-2 bullets
CORRECTIONS: each error as original → corrected (short reason)
IMPROVED VERSION: the student's letter rewritten at a strong B1 level (in Estonian)
''';

/// B1 writing task prompts modeled on the official format (isiklik kiri).
const _prompts = <(String et, String en)>[
  (
    'Kirjuta kiri sõbrale ja kutsu ta nädalavahetusel külla. Kirjuta, mida te koos teete.',
    'Write a letter to a friend inviting them to visit at the weekend. Say what you will do together.'
  ),
  (
    'Kirjuta kiri sõbrale oma uuest töökohast. Kirjelda oma tööd ja kolleege.',
    'Write a letter to a friend about your new job. Describe the work and your colleagues.'
  ),
  (
    'Kirjuta kiri sõbrale ja räägi oma viimasest reisist. Mis sulle meeldis ja mis mitte?',
    'Write a letter about your last trip. What did you like and what not?'
  ),
  (
    'Sa ei saa homme keeltekursusele tulla. Kirjuta õpetajale ja selgita, miks.',
    "You can't attend tomorrow's language course. Write to the teacher and explain why."
  ),
  (
    'Kirjuta sõbrale oma uuest korterist. Kirjelda tube ja ümbruskonda.',
    'Write to a friend about your new flat. Describe the rooms and the neighbourhood.'
  ),
];

class WriteTab extends StatefulWidget {
  final Repo repo;
  final RadaTokens tokens;
  final L10n l;
  final SpeechConfig config;

  const WriteTab({
    super.key,
    required this.repo,
    required this.tokens,
    required this.l,
    required this.config,
  });

  @override
  State<WriteTab> createState() => _WriteTabState();
}

class _WriteTabState extends State<WriteTab> {
  int _index = Random().nextInt(_prompts.length);
  final _text = TextEditingController();
  bool _busy = false;
  String? _feedback;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _wordCount =>
      _text.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  Future<void> _submit() async {
    if (_wordCount < 20) return;
    setState(() {
      _busy = true;
      _error = null;
      _feedback = null;
    });
    final started = DateTime.now();
    try {
      final reply = await widget.config.llm.chat(
        system: _writeSystem,
        messages: [
          ChatMsg('user',
              'Task: ${_prompts[_index].$1}\n\nStudent letter:\n${_text.text}'),
        ],
      );
      final mins =
          max(1, DateTime.now().difference(started).inMinutes + 5);
      await widget.repo.db.into(widget.repo.db.practiceSessions).insert(
            PracticeSessionsCompanion.insert(
              id: 'ps-${DateTime.now().microsecondsSinceEpoch}',
              mode: 'write',
              startedAt: started,
              durationS: Value(mins * 60),
              llmBackend: Value(widget.config.llm.backendLabel),
              payloadJson: Value(jsonEncode({
                'prompt': _prompts[_index].$1,
                'text': _text.text,
                'feedback': reply,
              })),
            ),
          );
      await widget.repo
          .logActivity(mins, 'writing', detail: {'words': _wordCount});
      setState(() {
        _feedback = reply;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final l = widget.l;
    final (et, en) = _prompts[_index];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            title: Text(et),
            subtitle: Text(en, style: TextStyle(color: t.textSecondary)),
            trailing: IconButton(
              tooltip: l.t('Another task', 'Teine ülesanne'),
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() {
                _index = (_index + 1) % _prompts.length;
                _feedback = null;
              }),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _text,
          maxLines: 10,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: l.t('Write your letter in Estonian (80–120 words)…',
                'Kirjuta oma kiri siia (80–120 sõna)…'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text('$_wordCount ${l.t('words', 'sõna')}',
                  style: TextStyle(
                      color: _wordCount >= 80 && _wordCount <= 130
                          ? t.success
                          : t.textSecondary)),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.school),
                label: Text(l.t('Get feedback', 'Saa tagasisidet')),
                onPressed: _busy || _wordCount < 20 ? null : _submit,
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        if (_feedback != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(_feedback!),
            ),
          ),
      ],
    );
  }
}
