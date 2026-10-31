import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/db.dart';
import '../data/repo.dart';

/// Initializes Supabase from in-app settings (settings_kv) — B1 fix: the
/// user consumes CI binaries, so configuration must live in the app.
/// Returns true when configured. Safe to call again after settings change
/// (re-initialization with new values requires an app restart; we report
/// the current state honestly).
Future<bool> initSupabaseFromSettings(Repo repo) async {
  final url = (await repo.getSetting('supabase_url') ?? '').trim();
  final key = (await repo.getSetting('supabase_key') ?? '').trim();
  if (url.isEmpty || key.isEmpty) return false;
  try {
    try {
      // Already initialized? (throws if not)
      Supabase.instance.client;
      return true;
    } catch (_) {}
    await Supabase.initialize(url: url, publishableKey: key);
    return true;
  } catch (_) {
    return false;
  }
}

/// All timestamps cross the wire as UTC ISO-8601 (B4 fix). Local DateTimes
/// are converted on push and back to local on pull so calendar-day
/// bucketing (activity_log.date) survives the round trip.
String _utc(DateTime d) => d.toUtc().toIso8601String();
DateTime _local(String iso) => DateTime.parse(iso).toLocal();

/// Spec §9 — Supabase courier, local-first, LWW per row on updated_at.
/// Tables: progress_entries, activity_log (append-only), mock_exams
/// (append-only), answer_keys, exam_plans.
class SyncService {
  final SupabaseClient _client;
  final RadaDb _db;
  final String deviceId;

  SyncService(this._client, this._db, {required this.deviceId});

  Future<String> syncNow() async {
    final p = await _syncProgress();
    final a = await _syncActivity();
    final m = await _syncMocks();
    final k = await _syncAnswerKeys();
    final e = await _syncExamPlans();
    return 'progress $p · activity $a · mocks $m · keys $k · exam $e';
  }

  // ---- progress_entries (LWW) ------------------------------------------------

  Future<String> _syncProgress() async {
    final local = await _db.select(_db.progressEntries).get();
    final remote = List<Map<String, dynamic>>.from(
        await _client.from('progress_entries').select());
    final remoteById = {for (final r in remote) r['id'] as String: r};

    final toPush = <Map<String, dynamic>>[];
    for (final row in local) {
      final r = remoteById[row.id];
      if (r == null ||
          _local(r['updated_at'] as String).isBefore(row.updatedAt)) {
        toPush.add({
          'id': row.id,
          'target_type': row.targetType,
          'target_id': row.targetId,
          'status': row.status,
          'completed_at':
              row.completedAt == null ? null : _utc(row.completedAt!),
          'self_score': row.selfScore,
          'note': row.note,
          'created_at': _utc(row.createdAt),
          'updated_at': _utc(row.updatedAt),
          'device_id': deviceId,
          'deleted': row.deleted,
        });
      }
    }
    if (toPush.isNotEmpty) {
      await _client.from('progress_entries').upsert(toPush);
    }

    final localById = {for (final r in local) r.id: r};
    var pulled = 0;
    for (final r in remote) {
      final id = r['id'] as String;
      final lrow = localById[id];
      final rUpdated = _local(r['updated_at'] as String);
      if (lrow == null || lrow.updatedAt.isBefore(rUpdated)) {
        await _db.into(_db.progressEntries).insert(
              ProgressEntriesCompanion.insert(
                id: id,
                targetType: r['target_type'] as String,
                targetId: r['target_id'] as String,
                status: Value(r['status'] as String? ?? 'todo'),
                completedAt: Value(r['completed_at'] == null
                    ? null
                    : _local(r['completed_at'] as String)),
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

  // ---- activity_log (append-only) ----------------------------------------------

  Future<String> _syncActivity() async {
    final local = await _db.select(_db.activityLog).get();
    final remote = List<Map<String, dynamic>>.from(
        await _client.from('activity_log').select());
    final remoteIds = {for (final r in remote) r['id'] as String};
    final localIds = {for (final r in local) r.id};

    final toPush = local
        .where((r) => !remoteIds.contains(r.id))
        .map((row) => {
              'id': row.id,
              'date': _utc(row.date),
              'minutes': row.minutes,
              'kind': row.kind,
              'detail_json': row.detailJson,
              'created_at': _utc(row.createdAt),
              'updated_at': _utc(row.updatedAt),
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
              date: _local(r['date'] as String),
              minutes: r['minutes'] as int,
              kind: r['kind'] as String,
              detailJson: Value(r['detail_json'] as String?),
              updatedAt: Value(_local(r['updated_at'] as String)),
              deviceId: Value(r['device_id'] as String? ?? 'remote'),
            ),
            mode: InsertMode.insertOrReplace,
          );
      pulled++;
    }
    return '↑${toPush.length} ↓$pulled';
  }

  // ---- mock_exams (append-only) -----------------------------------------------

  Future<String> _syncMocks() async {
    final local = await _db.select(_db.mockExams).get();
    final remote = List<Map<String, dynamic>>.from(
        await _client.from('mock_exams').select());
    final remoteIds = {for (final r in remote) r['id'] as String};
    final localIds = {for (final r in local) r.id};

    final toPush = local
        .where((r) => !remoteIds.contains(r.id))
        .map((row) => {
              'id': row.id,
              'started_at': _utc(row.startedAt),
              'sections_json': row.sectionsJson,
              'total_pct': row.totalPct,
              'notes': row.notes,
              'created_at': _utc(row.createdAt),
              'updated_at': _utc(row.updatedAt),
              'device_id': deviceId,
              'deleted': row.deleted,
            })
        .toList();
    if (toPush.isNotEmpty) await _client.from('mock_exams').upsert(toPush);

    var pulled = 0;
    for (final r in remote) {
      if (localIds.contains(r['id'] as String)) continue;
      await _db.into(_db.mockExams).insert(
            MockExamsCompanion.insert(
              id: r['id'] as String,
              startedAt: _local(r['started_at'] as String),
              sectionsJson: r['sections_json'] as String,
              totalPct: Value((r['total_pct'] as num?)?.toDouble()),
              notes: Value(r['notes'] as String?),
              updatedAt: Value(_local(r['updated_at'] as String)),
              deviceId: Value(r['device_id'] as String? ?? 'remote'),
            ),
            mode: InsertMode.insertOrReplace,
          );
      pulled++;
    }
    return '↑${toPush.length} ↓$pulled';
  }

  // ---- answer_keys (LWW) ----------------------------------------------------------

  Future<String> _syncAnswerKeys() async {
    final local = await _db.select(_db.answerKeys).get();
    final remote = List<Map<String, dynamic>>.from(
        await _client.from('answer_keys').select());
    final remoteById = {for (final r in remote) r['id'] as String: r};

    final toPush = <Map<String, dynamic>>[];
    for (final row in local) {
      final r = remoteById[row.id];
      if (r == null ||
          _local(r['updated_at'] as String).isBefore(row.updatedAt)) {
        toPush.add({
          'id': row.id,
          'exam_asset_id': row.examAssetId,
          'answers_json': row.answersJson,
          'created_at': _utc(row.createdAt),
          'updated_at': _utc(row.updatedAt),
          'device_id': deviceId,
          'deleted': row.deleted,
        });
      }
    }
    if (toPush.isNotEmpty) await _client.from('answer_keys').upsert(toPush);

    final localById = {for (final r in local) r.id: r};
    var pulled = 0;
    for (final r in remote) {
      final id = r['id'] as String;
      final rUpdated = _local(r['updated_at'] as String);
      final lrow = localById[id];
      if (lrow == null || lrow.updatedAt.isBefore(rUpdated)) {
        await _db.into(_db.answerKeys).insert(
              AnswerKeysCompanion.insert(
                id: id,
                examAssetId: r['exam_asset_id'] as String,
                answersJson: r['answers_json'] as String,
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

  // ---- exam_plans (LWW) -------------------------------------------------------------

  Future<String> _syncExamPlans() async {
    final local = await _db.select(_db.examPlans).get();
    final remote = List<Map<String, dynamic>>.from(
        await _client.from('exam_plans').select());
    final remoteById = {for (final r in remote) r['id'] as String: r};

    final toPush = <Map<String, dynamic>>[];
    for (final row in local) {
      final r = remoteById[row.id];
      if (r == null ||
          _local(r['updated_at'] as String).isBefore(row.updatedAt)) {
        toPush.add({
          'id': row.id,
          'exam_date': _utc(row.examDate),
          'registration_deadline': _utc(row.registrationDeadline),
          'consultation_date': row.consultationDate == null
              ? null
              : _utc(row.consultationDate!),
          'registered': row.registered,
          'location': row.location,
          'created_at': _utc(row.createdAt),
          'updated_at': _utc(row.updatedAt),
          'device_id': deviceId,
          'deleted': row.deleted,
        });
      }
    }
    if (toPush.isNotEmpty) await _client.from('exam_plans').upsert(toPush);

    final localById = {for (final r in local) r.id: r};
    var pulled = 0;
    for (final r in remote) {
      final id = r['id'] as String;
      final rUpdated = _local(r['updated_at'] as String);
      final lrow = localById[id];
      if (lrow == null || lrow.updatedAt.isBefore(rUpdated)) {
        await _db.into(_db.examPlans).insert(
              ExamPlansCompanion.insert(
                id: id,
                examDate: _local(r['exam_date'] as String),
                registrationDeadline:
                    _local(r['registration_deadline'] as String),
                consultationDate: Value(r['consultation_date'] == null
                    ? null
                    : _local(r['consultation_date'] as String)),
                registered: Value(r['registered'] as bool? ?? false),
                location: Value(r['location'] as String?),
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
}
