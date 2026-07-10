import 'dart:io' show Platform;

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/db.dart';
import '../../services/sync_service.dart';
import '../../theme/themes.dart';
import '../../theme/tokens.dart';

/// M0 placeholder dashboard: proves DB seed, theme switching, and the
/// Supabase round-trip. The real Trail home screen replaces this in M1.
class DashboardScreen extends StatefulWidget {
  final RadaDb db;
  final RadaTokens tokens;
  final bool syncConfigured;
  final ValueChanged<RadaTokens> onThemeChanged;

  const DashboardScreen({
    super.key,
    required this.db,
    required this.tokens,
    required this.syncConfigured,
    required this.onThemeChanged,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _chaptersTotal = 0;
  int _chaptersDone = 0;
  String _syncStatus = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final chapters = await widget.db.select(widget.db.chapters).get();
    final done = await (widget.db.select(widget.db.progressEntries)
          ..where((p) => p.status.equals('done')))
        .get();
    setState(() {
      _chaptersTotal = chapters.length; // 29 when seeded
      _chaptersDone = done.length;
    });
  }

  Future<void> _syncTest() async {
    if (!widget.syncConfigured) {
      setState(() => _syncStatus = 'Supabase not configured (.env) — see README.');
      return;
    }
    try {
      final sync = SyncService(Supabase.instance.client,
          deviceId: Platform.operatingSystem);
      await sync.pushProbe('tere from ${Platform.operatingSystem} '
          '@ ${DateTime.now().toIso8601String()}');
      final probes = await sync.fetchProbes();
      setState(() => _syncStatus =
          'OK — ${probes.length} probe(s) visible. Latest: ${probes.first['message']}');
    } catch (e) {
      setState(() => _syncStatus = 'Sync failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final pct = _chaptersTotal == 0 ? 0.0 : _chaptersDone / _chaptersTotal;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rada — M0'),
        actions: [
          PopupMenuButton<RadaTokens>(
            icon: const Icon(Icons.palette_outlined),
            onSelected: widget.onThemeChanged,
            itemBuilder: (_) => [
              for (final theme in allThemes)
                PopupMenuItem(value: theme, child: Text(theme.name)),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rada 0 → B1',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(t.radius),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 10,
                      color: t.accent,
                      backgroundColor: t.surfaceAlt,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('$_chaptersDone / $_chaptersTotal peatükki '
                      '(Keeleklikk 16 + Keeletee 13)'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Icon(Icons.local_fire_department, color: t.warning),
              title: const Text('Streak: 0 päeva'),
              subtitle: const Text('Real streak logic lands in M1 (activity_log).'),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('M0 acceptance — sync round-trip',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _syncTest,
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync test'),
                  ),
                  if (_syncStatus.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_syncStatus),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Dev helper: tick a chapter to see the progress bar move.
          OutlinedButton(
            onPressed: () async {
              final chapters =
                  await widget.db.select(widget.db.chapters).get();
              if (_chaptersDone < chapters.length) {
                final next = chapters[_chaptersDone];
                await widget.db.into(widget.db.progressEntries).insert(
                      ProgressEntriesCompanion.insert(
                        id: 'prog-${next.id}',
                        targetType: 'chapter',
                        targetId: next.id,
                        status: const Value('done'),
                        completedAt: Value(DateTime.now()),
                      ),
                      mode: InsertMode.insertOrReplace,
                    );
                await _load();
              }
            },
            child: const Text('[dev] mark next chapter done'),
          ),
        ],
      ),
    );
  }
}
