import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'db.g.dart';

/// Sync columns carried by every table (spec §4, §9).
mixin SyncColumns on Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get deviceId => text().withDefault(const Constant('unknown'))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ---- §4.1 Syllabus & progress -------------------------------------------

class Courses extends Table with SyncColumns {
  TextColumn get slug => text()(); // 'keeleklikk' | 'keeletee'
  TextColumn get title => text()();
  TextColumn get levelRange => text()(); // '0-A2' | 'A2-B1'
  IntColumn get chaptersTotal => integer()();
  TextColumn get baseUrl => text()();
  TextColumn get teacherEmail => text().nullable()();
}

class Chapters extends Table with SyncColumns {
  TextColumn get courseId => text().references(Courses, #id)();
  IntColumn get index => integer()();
  TextColumn get titleEt => text()();
  TextColumn get titleEn => text().nullable()();
  TextColumn get urlFragment => text().nullable()();
  IntColumn get estMinutes => integer().withDefault(const Constant(180))();
}

class ProgressEntries extends Table with SyncColumns {
  TextColumn get targetType => text()(); // 'chapter' | 'chapter_item'
  TextColumn get targetId => text()();
  TextColumn get status => text().withDefault(const Constant('todo'))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get selfScore => integer().nullable()();
  TextColumn get note => text().nullable()();
}

// ---- §4.2 Motivation ------------------------------------------------------

class ActivityLog extends Table with SyncColumns {
  DateTimeColumn get date => dateTime()();
  IntColumn get minutes => integer()();
  TextColumn get kind => text()(); // course|vocab|speech|exam_prep|writing
  TextColumn get detailJson => text().nullable()();
}

class ExamPlans extends Table with SyncColumns {
  DateTimeColumn get examDate => dateTime()();
  DateTimeColumn get registrationDeadline => dateTime()();
  DateTimeColumn get consultationDate => dateTime().nullable()();
  BoolColumn get registered => boolean().withDefault(const Constant(false))();
  TextColumn get location => text().nullable()();
}

// ---- §4.3 Vocabulary (FSRS) ------------------------------------------------

class VocabItems extends Table with SyncColumns {
  TextColumn get et => text()();
  TextColumn get en => text()();
  TextColumn get exampleEt => text().nullable()();
  TextColumn get exampleEn => text().nullable()();
  TextColumn get source => text().nullable()();
  DateTimeColumn get fsrsDue => dateTime().nullable()();
  RealColumn get fsrsStability => real().withDefault(const Constant(0))();
  RealColumn get fsrsDifficulty => real().withDefault(const Constant(0))();
  TextColumn get fsrsState => text().withDefault(const Constant('new'))();
}

class ReviewLog extends Table with SyncColumns {
  TextColumn get vocabItemId => text().references(VocabItems, #id)();
  DateTimeColumn get reviewedAt => dateTime()();
  TextColumn get rating => text()(); // again|hard|good|easy
}

// ---- §4.4 Practice & exam prep ----------------------------------------------

class PracticeSessions extends Table with SyncColumns {
  TextColumn get mode => text()(); // listen|pronounce|converse|write|mock_exam
  DateTimeColumn get startedAt => dateTime()();
  IntColumn get durationS => integer().withDefault(const Constant(0))();
  TextColumn get llmBackend => text().nullable()(); // local|cloud
  TextColumn get payloadJson => text().nullable()();
}

class ExamAssets extends Table with SyncColumns {
  TextColumn get kind => text()(); // pdf|mp3|link
  TextColumn get section => text()(); // kirjutamine|kuulamine|lugemine|raakimine|general
  TextColumn get title => text()();
  TextColumn get remoteUrl => text()();
  TextColumn get localPath => text().nullable()();
  TextColumn get sha256 => text().nullable()();
}

class MockExams extends Table with SyncColumns {
  DateTimeColumn get startedAt => dateTime()();
  TextColumn get sectionsJson => text()();
  RealColumn get totalPct => real().nullable()();
  TextColumn get notes => text().nullable()();
}

/// Hand-entered once per sample task (from the official PDFs) — enables
/// auto-grading of reading/listening mocks (spec §4.4).
class AnswerKeys extends Table with SyncColumns {
  TextColumn get examAssetId => text().references(ExamAssets, #id)();
  TextColumn get answersJson => text()(); // JSON array, index = question no.
}

/// Used only by the M0 sync acceptance test.
class SyncProbes extends Table with SyncColumns {
  TextColumn get message => text()();
}

/// Simple key-value settings (goal minutes, sync cursors, theme...).
class SettingsKv extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [
  Courses,
  Chapters,
  ProgressEntries,
  ActivityLog,
  ExamPlans,
  VocabItems,
  ReviewLog,
  PracticeSessions,
  ExamAssets,
  MockExams,
  SyncProbes,
  SettingsKv,
  AnswerKeys,
])
class RadaDb extends _$RadaDb {
  RadaDb() : super(driftDatabase(name: 'rada'));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(settingsKv);
          }
          if (from < 3) {
            await m.createTable(answerKeys);
          }
        },
      );
}
