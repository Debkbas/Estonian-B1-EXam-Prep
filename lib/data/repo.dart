import 'dart:convert';

import 'package:drift/drift.dart';

import 'db.dart';

/// Trail view model: courses in order, chapters in order, done-status map.
class TrailData {
  final List<Course> courses;
  final Map<String, List<Chapter>> chaptersByCourse;
  final Set<String> doneChapterIds;

  TrailData(this.courses, this.chaptersByCourse, this.doneChapterIds);

  int get totalChapters =>
      chaptersByCourse.values.fold(0, (a, l) => a + l.length);
  int get doneCount => doneChapterIds.length;

  /// First not-done chapter across the whole path, or null when finished.
  Chapter? get currentChapter {
    for (final c in courses) {
      for (final ch in chaptersByCourse[c.id] ?? const <Chapter>[]) {
        if (!doneChapterIds.contains(ch.id)) return ch;
      }
    }
    return null;
  }

  Course? courseOf(Chapter ch) {
    final matches = courses.where((c) => c.id == ch.courseId).toList();
    return matches.isEmpty ? null : matches.first;
  }
}

class Repo {
  final RadaDb db;
  Repo(this.db);

  // ---- trail -------------------------------------------------------------

  Future<TrailData> loadTrail() async {
    final courses = await (db.select(db.courses)
          ..orderBy([(c) => OrderingTerm.asc(c.levelRange)]))
        .get();
    final chapters = await (db.select(db.chapters)
          ..orderBy([(c) => OrderingTerm.asc(c.index)]))
        .get();
    final progress = await (db.select(db.progressEntries)
          ..where((p) => p.status.equals('done') & p.deleted.equals(false)))
        .get();

    final byCourse = <String, List<Chapter>>{};
    for (final ch in chapters) {
      byCourse.putIfAbsent(ch.courseId, () => []).add(ch);
    }
    final done = progress
        .where((p) => p.targetType == 'chapter')
        .map((p) => p.targetId)
        .toSet();
    return TrailData(courses, byCourse, done);
  }

  Future<void> setChapterDone(String chapterId, bool done) async {
    await db.into(db.progressEntries).insert(
          ProgressEntriesCompanion.insert(
            id: 'prog-$chapterId',
            targetType: 'chapter',
            targetId: chapterId,
            status: Value(done ? 'done' : 'todo'),
            completedAt: Value(done ? DateTime.now() : null),
            updatedAt: Value(DateTime.now()),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  // ---- activity / streak ---------------------------------------------------

  Future<void> logActivity(int minutes, String kind,
      {Map<String, Object?>? detail}) async {
    if (minutes <= 0) return;
    final now = DateTime.now();
    await db.into(db.activityLog).insert(ActivityLogCompanion.insert(
          id: 'act-${now.microsecondsSinceEpoch}',
          date: DateTime(now.year, now.month, now.day),
          minutes: minutes,
          kind: kind,
          detailJson: Value(detail == null ? null : jsonEncode(detail)),
          updatedAt: Value(now),
        ));
  }

  Future<Map<DateTime, int>> minutesByDay({int days = 120}) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final rows = await (db.select(db.activityLog)
          ..where((a) => a.date.isBiggerThanValue(since) &
              a.deleted.equals(false)))
        .get();
    final map = <DateTime, int>{};
    for (final r in rows) {
      final d = DateTime(r.date.year, r.date.month, r.date.day);
      map[d] = (map[d] ?? 0) + r.minutes;
    }
    return map;
  }

  // ---- settings -----------------------------------------------------------

  Future<String?> getSetting(String key) async {
    final row = await (db.select(db.settingsKv)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) async {
    await db.into(db.settingsKv).insert(
          SettingsKvCompanion.insert(key: key, value: value),
          mode: InsertMode.insertOrReplace,
        );
  }

  Future<int> goalMinutes() async =>
      int.tryParse(await getSetting('goal_minutes') ?? '') ?? 25;

  // ---- exam plan ------------------------------------------------------------

  Future<ExamPlan?> examPlan() async {
    final rows = await (db.select(db.examPlans)
          ..where((e) => e.deleted.equals(false))
          ..orderBy([(e) => OrderingTerm.asc(e.examDate)]))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> setExamDate(DateTime examDate) async {
    // B1 registration typically closes ~5 weeks before (see spec appendix).
    final regDeadline = examDate.subtract(const Duration(days: 36));
    await db.into(db.examPlans).insert(
          ExamPlansCompanion.insert(
            id: 'exam-plan-1',
            examDate: examDate,
            registrationDeadline: regDeadline,
            updatedAt: Value(DateTime.now()),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }
}
