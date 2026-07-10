import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/db.dart';

/// Spec §9 — Supabase courier, local-first, LWW per row on updated_at.
/// M1 scope: progress_entries + activity_log (the tables the study loop
/// writes). Data volume is tiny (single user), so full-table reconcile
/// is simpler and safer than cursors.
class SyncService {
  final SupabaseClient _client;
  final RadaDb _db;
  final String deviceId;

  SyncService(this._client, this._db, {required this.deviceId});

  Future<String> syncNow() async {
    final p = await _syncProgress();
    final a = await _syncActivity();
    return 'progress: $p · activity: $a';
  }

  Future<String> _syncProgress() async {
    final local = await _db.select(_db.progressEntries).get();
    final remote = List<Map<String, dynamic>>.from(
        await _client.from('progress_entries').select());
    final remoteById = {for (final r in remote) r['id'] as String: r};

    // push local rows that are newer or missing remotely
    final toPush = <Map<String, dynamic>>[];
    for (final row in local) {
      final r = remoteById[row.id];
      if (r == null ||
          DateTime.parse(r['updated_at'] as String)
              .isBefore(row.updatedAt)) {
        toPush.add({
          'id': row.id,
          'target_type': row.targetType,
          'target_id': row.targetId,
          'status': row.status,
          'completed_at': row.completedAt?.toIso8601String(),
          'self_score': row.selfScore,
          'note': row.note,
          'created_at': row.createdAt.toIso8601String(),
          'updated_at': row.updatedAt.toIso8601String(),
          'device_id': deviceId,
          'deleted': row.deleted,
        });
      }
    }
    if (toPush.isNotEmpty) {
      await _client.from('progress_entries').upsert(toPush);
    }

    // pull remote rows that are newer or missing locally
    final localById = {for (final r in local) r.id: r};
    var pulled = 0;
    for (final r in remote) {
      final id = r['id'] as String;
      final lrow = localById[id];
      final rUpdated = DateTime.parse(r['updated_at'] as String);
      if (lrow == null || lrow.updatedAt.isBefore(rUpdated)) {
        await _db.into(_db.progressEntries).insert(
              ProgressEntriesCompanion.insert(
                id: id,
                targetType: r['target_type'] as String,
                targetId: r['target_id'] as String,
                status: Value(r['status'] as String? ?? 'todo'),
                completedAt: Value(r['completed_at'] == null
                    ? null
                    : DateTime.parse(r['completed_at'] as String)),
                selfScore: Value(r['self_score'] as int?),
                note: Value(r['note'] as String?),
                updatedAt: Value(rUpdated),
                deviceId: Value(r['device_id'] as String? ?? 'remote'),
                deleted: Value(r['deleted'] as bool? ?? false),
              ),
              mode: InsertMode.insertOrReplace,
            );
        pulled++;
      }
    }
    return '↑${toPush.length} ↓$pulled';
  }

  Future<String> _syncActivity() async {
    // append-only table: union of ids
    final local = await _db.select(_db.activityLog).get();
    final remote = List<Map<String, dynamic>>.from(
        await _client.from('activity_log').select());
    final remoteIds = {for (final r in remote) r['id'] as String};
    final localIds = {for (final r in local) r.id};

    final toPush = local
        .where((r) => !remoteIds.contains(r.id))
        .map((row) => {
              'id': row.id,
              'date': row.date.toIso8601String(),
              'minutes': row.minutes,
              'kind': row.kind,
              'detail_json': row.detailJson,
              'created_at': row.createdAt.toIso8601String(),
              'updated_at': row.updatedAt.toIso8601String(),
              'device_id': deviceId,
              'deleted': row.deleted,
            })
        .toList();
    if (toPush.isNotEmpty) {
      await _client.from('activity_log').upsert(toPush);
    }

    var pulled = 0;
    for (final r in remote) {
      if (localIds.contains(r['id'] as String)) continue;
      await _db.into(_db.activityLog).insert(
            ActivityLogCompanion.insert(
              id: r['id'] as String,
              date: DateTime.parse(r['date'] as String),
              minutes: r['minutes'] as int,
              kind: r['kind'] as String,
              detailJson: Value(r['detail_json'] as String?),
              updatedAt:
                  Value(DateTime.parse(r['updated_at'] as String)),
              deviceId: Value(r['device_id'] as String? ?? 'remote'),
            ),
            mode: InsertMode.insertOrReplace,
          );
      pulled++;
    }
    return '↑${toPush.length} ↓$pulled';
  }
}
