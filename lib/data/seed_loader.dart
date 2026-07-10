import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'db.dart';

/// Idempotent: seeds courses + chapters from assets/seed/syllabus.json
/// if the courses table is empty (spec §4.1 — syllabus is seed data,
/// never scraped).
Future<void> seedSyllabusIfEmpty(RadaDb db) async {
  final existing = await db.select(db.courses).get();
  if (existing.isNotEmpty) return;

  final raw = await rootBundle.loadString('assets/seed/syllabus.json');
  final json = jsonDecode(raw) as Map<String, dynamic>;

  await db.batch((b) {
    for (final c in (json['courses'] as List).cast<Map<String, dynamic>>()) {
      b.insert(
        db.courses,
        CoursesCompanion.insert(
          id: c['id'] as String,
          slug: c['slug'] as String,
          title: c['title'] as String,
          levelRange: c['level_range'] as String,
          chaptersTotal: c['chapters_total'] as int,
          baseUrl: c['base_url'] as String,
        ),
      );
      for (final ch in (c['chapters'] as List).cast<Map<String, dynamic>>()) {
        b.insert(
          db.chapters,
          ChaptersCompanion.insert(
            id: ch['id'] as String,
            courseId: c['id'] as String,
            index: ch['index'] as int,
            titleEt: ch['title_et'] as String,
            estMinutes: Value(ch['est_minutes'] as int? ?? 180),
          ),
        );
      }
    }
  });
}
