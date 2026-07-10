import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/db.dart';
import '../../data/repo.dart';
import '../../domain/l10n.dart';
import '../../domain/streak.dart';
import '../../services/sync_service.dart';
import '../../theme/themes.dart';
import '../../theme/tokens.dart';
import '../course/course_webview_screen.dart';
import '../vault/vault_screen.dart';

/// The Trail — signature home screen (spec §8.2).
class TrailScreen extends StatefulWidget {
  final RadaDb db;
  final RadaTokens tokens;
  final bool syncConfigured;
  final ValueChanged<RadaTokens> onThemeChanged;

  const TrailScreen({
    super.key,
    required this.db,
    required this.tokens,
    required this.syncConfigured,
    required this.onThemeChanged,
  });

  @override
  State<TrailScreen> createState() => _TrailScreenState();
}

class _TrailScreenState extends State<TrailScreen> {
  late final Repo _repo = Repo(widget.db);

  TrailData? _trail;
  Map<DateTime, int> _minutes = {};
  int _goal = 25;
  int _streak = 0;
  ExamPlan? _plan;
  String _syncMsg = '';
  L10n _l = const L10n('both');

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final trail = await _repo.loadTrail();
    final minutes = await _repo.minutesByDay();
    final goal = await _repo.goalMinutes();
    final plan = await _repo.examPlan();
    final lang = await _repo.getSetting('ui_lang') ?? 'both';
    if (!mounted) return;
    setState(() {
      _trail = trail;
      _minutes = minutes;
      _goal = goal;
      _streak = currentStreak(minutes, goal);
      _plan = plan;
      _l = L10n(lang);
    });
  }

  int get _todayMinutes {
    final now = DateTime.now();
    return _minutes[DateTime(now.year, now.month, now.day)] ?? 0;
  }

  Future<void> _openCourse(Course course, {String? fragment}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CourseWebviewScreen(
        repo: _repo,
        title: course.title,
        url: fragment == null ? course.baseUrl : '${course.baseUrl}$fragment',
        courseSlug: course.slug,
      ),
    ));
    _refresh();
  }

  Future<void> _syncNow() async {
    if (!widget.syncConfigured) {
      setState(() => _syncMsg = _l.t('Supabase not configured (.env)',
          'Supabase pole seadistatud (.env)'));
      return;
    }
    setState(() => _syncMsg = _l.t('syncing…', 'sünkimine…'));
    try {
      final sync = SyncService(Supabase.instance.client, widget.db,
          deviceId: Platform.operatingSystem);
      final result = await sync.syncNow();
      setState(() => _syncMsg = result);
      _refresh();
    } catch (e) {
      setState(() => _syncMsg = 'viga: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final trail = _trail;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rada'),
        actions: [
          IconButton(
            tooltip: _l.t('Exam vault', 'Eksami varamu'),
            icon: const Icon(Icons.library_books_outlined),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => VaultScreen(
                    repo: _repo, tokens: widget.tokens, l: _l),
              ));
              _refresh();
            },
          ),
          IconButton(
            tooltip: _l.t('Sync', 'Sünki'),
            icon: const Icon(Icons.sync),
            onPressed: _syncNow,
          ),
          IconButton(
            tooltip: _l.t('Settings', 'Seaded'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: trail == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _statusRow(t, trail),
                  const SizedBox(height: 12),
                  _questCard(t, trail),
                  const SizedBox(height: 12),
                  _heatmapCard(t),
                  if (_syncMsg.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_syncMsg,
                          style: TextStyle(color: t.textSecondary)),
                    ),
                  const SizedBox(height: 16),
                  for (final course in trail.courses) ...[
                    _courseHeader(t, course, trail),
                    for (final ch in trail.chaptersByCourse[course.id] ??
                        const <Chapter>[])
                      _waypoint(t, trail, course, ch),
                  ],
                  _examFlag(t, trail),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  // ---- header row: streak · progress · exam countdown -----------------------

  Widget _statusRow(RadaTokens t, TrailData trail) {
    final daysLeft = _plan?.examDate.difference(DateTime.now()).inDays;
    return Row(
      children: [
        _chip(t, Icons.local_fire_department,
            _l.short('$_streak days', '$_streak päeva'),
            _streak > 0 ? t.warning : t.textSecondary),
        const SizedBox(width: 8),
        _chip(t, Icons.flag_outlined,
            '${trail.doneCount}/${trail.totalChapters}', t.accent),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: _pickExamDate,
            borderRadius: BorderRadius.circular(t.radius),
            child: _chip(
                t,
                Icons.event,
                daysLeft == null
                    ? _l.t('set exam date', 'vali eksami kuupäev')
                    : _l.t('exam in $daysLeft days',
                        'eksamini $daysLeft päeva'),
                daysLeft != null && daysLeft < 60
                    ? t.warning
                    : t.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _chip(RadaTokens t, IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(t.radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ---- daily quest card (spec §8.1) -----------------------------------------

  Widget _questCard(RadaTokens t, TrailData trail) {
    final next = trail.currentChapter;
    final course = next == null ? null : trail.courseOf(next);
    final minutesPct = (_todayMinutes / _goal).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_l.t("Today's goal", 'Tänane siht'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                    minutesPct >= 1.0
                        ? Icons.check_circle
                        : Icons.timer_outlined,
                    color: minutesPct >= 1.0 ? t.success : t.accent),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        '${_l.t('Study $_goal min', 'Õpi $_goal min')} '
                        '($_todayMinutes/$_goal)')),
                IconButton(
                  tooltip: _l.t('+15 min studied elsewhere',
                      '+15 min mujal õpitud'),
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () async {
                    await _repo.logActivity(15, 'course',
                        detail: {'manual': true});
                    _refresh();
                  },
                ),
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(t.radius),
              child: LinearProgressIndicator(
                value: minutesPct,
                minHeight: 8,
                color: minutesPct >= 1.0 ? t.success : t.accent,
                backgroundColor: t.surface,
              ),
            ),
            const SizedBox(height: 12),
            if (next != null && course != null)
              Row(
                children: [
                  Icon(Icons.school_outlined, color: t.accent),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          '${_l.t('Next', 'Järgmine')}: ${course.title} — ${next.titleEt}')),
                  FilledButton(
                    onPressed: () => _openCourse(course),
                    child: Text(_l.short('Continue', 'Jätka')),
                  ),
                ],
              )
            else
              Row(children: [
                Icon(Icons.emoji_events, color: t.success),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_l.t('All chapters done — exam phase!',
                        'Kõik peatükid tehtud — eksamifaas!'))),
              ]),
          ],
        ),
      ),
    );
  }

  // ---- heat-map (last 15 weeks) ----------------------------------------------

  Widget _heatmapCard(RadaTokens t) {
    const weeks = 15;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // grid: columns = weeks, rows = mon..sun
    final firstMonday = today
        .subtract(Duration(days: (weeks - 1) * 7 + (today.weekday - 1)));

    Color cell(int m) {
      if (m <= 0) return t.surface;
      if (m < _goal ~/ 2) return t.accent.withValues(alpha: 0.25);
      if (m < _goal) return t.accent.withValues(alpha: 0.55);
      return t.accent;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_l.t('Last $weeks weeks', 'Viimased $weeks nädalat'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var w = 0; w < weeks; w++)
                  Column(
                    children: [
                      for (var d = 0; d < 7; d++)
                        Builder(builder: (_) {
                          final day =
                              firstMonday.add(Duration(days: w * 7 + d));
                          final m = day.isAfter(today)
                              ? -1
                              : (_minutes[day] ?? 0);
                          return Container(
                            width: 14,
                            height: 14,
                            margin: const EdgeInsets.all(1.5),
                            decoration: BoxDecoration(
                              color: m < 0 ? Colors.transparent : cell(m),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- trail waypoints ---------------------------------------------------------

  Widget _courseHeader(RadaTokens t, Course course, TrailData trail) {
    final chapters = trail.chaptersByCourse[course.id] ?? const <Chapter>[];
    final done =
        chapters.where((c) => trail.doneChapterIds.contains(c.id)).length;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Row(
        children: [
          Text('${course.title}  ·  ${course.levelRange}',
              style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          Text('$done/${chapters.length}',
              style: TextStyle(color: t.textSecondary)),
          IconButton(
            tooltip: _l.t('Open course', 'Ava kursus'),
            icon: Icon(Icons.open_in_new, size: 18, color: t.accent),
            onPressed: () => _openCourse(course),
          ),
        ],
      ),
    );
  }

  Widget _waypoint(RadaTokens t, TrailData trail, Course course, Chapter ch) {
    final done = trail.doneChapterIds.contains(ch.id);
    final isCurrent = trail.currentChapter?.id == ch.id;

    return InkWell(
      onTap: () => _chapterSheet(course, ch, done),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Column(
                children: [
                  Container(width: 2, height: 8, color: t.surfaceAlt),
                  Container(
                    width: isCurrent ? 22 : 16,
                    height: isCurrent ? 22 : 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? t.accent : t.surfaceAlt,
                      border: isCurrent
                          ? Border.all(color: t.accentAlt, width: 3)
                          : null,
                    ),
                    child: done
                        ? const Icon(Icons.check, size: 12, color: Colors.white)
                        : null,
                  ),
                  Container(width: 2, height: 8, color: t.surfaceAlt),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ch.titleEt,
                style: TextStyle(
                  color: done
                      ? t.textSecondary
                      : (isCurrent ? t.textPrimary : t.textSecondary),
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (isCurrent)
              Icon(Icons.person_pin_circle, color: t.accentAlt, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _examFlag(RadaTokens t, TrailData trail) {
    final allDone = trail.doneCount >= trail.totalChapters;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Icon(Icons.flag,
                color: allDone ? t.success : t.textSecondary, size: 28),
          ),
          const SizedBox(width: 8),
          Text('B1 eksam',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: allDone ? t.success : t.textSecondary)),
        ],
      ),
    );
  }

  // ---- sheets & dialogs ------------------------------------------------------

  Future<void> _chapterSheet(Course course, Chapter ch, bool done) async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('${course.title} — ${ch.titleEt}'),
              subtitle: Text(done
                  ? _l.t('Done', 'Tehtud')
                  : _l.t('Not done', 'Tegemata')),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(_l.t('Open course', 'Ava kursus')),
              onTap: () {
                Navigator.pop(ctx);
                _openCourse(course, fragment: ch.urlFragment);
              },
            ),
            ListTile(
              leading: Icon(done ? Icons.undo : Icons.check_circle_outline),
              title: Text(done
                  ? _l.t('Mark not done', 'Märgi tegemata')
                  : _l.t('Mark done', 'Märgi tehtuks')),
              onTap: () async {
                Navigator.pop(ctx);
                await _repo.setChapterDone(ch.id, !done);
                _refresh();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickExamDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _plan?.examDate ?? DateTime(2026, 11, 8),
      firstDate: now,
      lastDate: now.add(const Duration(days: 900)),
    );
    if (picked != null) {
      await _repo.setExamDate(picked);
      _refresh();
    }
  }

  Future<void> _openSettings() async {
    final goalCtl = TextEditingController(text: '$_goal');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_l.t('Settings', 'Seaded'),
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(_l.t('App language', 'Rakenduse keel'),
                style: Theme.of(ctx).textTheme.titleSmall),
            Wrap(
              spacing: 8,
              children: [
                for (final m in L10n.modes)
                  ChoiceChip(
                    label: Text(L10n.modeLabel(m)),
                    selected: _l.mode == m,
                    onSelected: (_) async {
                      await _repo.setSetting('ui_lang', m);
                      if (ctx.mounted) Navigator.pop(ctx);
                      _refresh();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(_l.t('Theme', 'Teema'),
                style: Theme.of(ctx).textTheme.titleSmall),
            Wrap(
              spacing: 8,
              children: [
                for (final theme in allThemes)
                  ChoiceChip(
                    label: Text(theme.name),
                    selected: widget.tokens.name == theme.name,
                    onSelected: (_) {
                      widget.onThemeChanged(theme);
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: goalCtl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText:
                    _l.t('Daily goal (minutes)', 'Päevane siht (minutit)'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(
                  onPressed: () async {
                    final v = int.tryParse(goalCtl.text);
                    if (v != null && v > 0) {
                      await _repo.setSetting('goal_minutes', '$v');
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    _refresh();
                  },
                  child: Text(_l.short('Save', 'Salvesta')),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _pickExamDate();
                  },
                  child: Text(_l.t('Exam date', 'Eksami kuupäev')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
