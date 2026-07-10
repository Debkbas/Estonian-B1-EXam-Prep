import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'db.dart';

/// Official Harno B1 materials — URLs verified July 2026 (spec §7, Appendix A).
/// Downloaded on-device by AssetService; nothing is redistributed.
/// Title convention: "<Group> · <what>" — mock runner pairs a task PDF with
/// its audio by matching the group prefix before '·'.
const _examAssetsSeed = [
  // general
  ('g1', 'pdf', 'general', 'Konsultatsioonivihik · B1 töövihik',
      'https://harno.ee/sites/default/files/documents/2026-01/B1_konsultatsioon_2021.pdf'),
  ('g2', 'pdf', 'general', 'Sooritusnäidis · hinnatud näidis',
      'https://harno.ee/sites/default/files/documents/2021-07/B1-taseme-sooritusnaidis.pdf'),
  ('g3', 'pdf', 'general', 'Käsiraamat · Iseseisev keelekasutaja',
      'https://harno.ee/sites/default/files/documents/2021-06/Iseseisev-keelekasutaja.pdf'),
  // kirjutamine
  ('w1', 'pdf', 'kirjutamine', 'Kirjutamine · isiklik kiri',
      'https://harno.ee/sites/default/files/documents/2021-06/B1_Ki2B_isiklik-kiri.pdf'),
  // kuulamine (task PDFs + audio)
  ('k1', 'pdf', 'kuulamine', 'Kuulamine 1 · ülesanne',
      'https://harno.ee/sites/default/files/documents/2021-06/B1_Ku1_yl_2020.pdf'),
  ('k1a', 'mp3', 'kuulamine', 'Kuulamine 1 · heli',
      'https://projektid.edu.ee/download/attachments/343705183/B1%20kuulamis%C3%BClesanne%20nr%201.mp3?version=1&modificationDate=1769079737638&api=v2'),
  ('k2', 'pdf', 'kuulamine', 'Kuulamine 2 · ülesanne',
      'https://harno.ee/sites/default/files/documents/2021-06/B1_ku2_yl_2020.pdf'),
  ('k2a', 'mp3', 'kuulamine', 'Kuulamine 2 · heli',
      'https://projektid.edu.ee/download/attachments/343705183/B1%20kuulamis%C3%BClesanne%20nr%202.mp3?version=1&modificationDate=1769079738169&api=v2'),
  ('k3', 'pdf', 'kuulamine', 'Kuulamine 3 · ülesanne',
      'https://harno.ee/sites/default/files/documents/2021-06/B1_Ku3_yl_l%C3%BCnk%C3%BClesanne.pdf'),
  ('k3a', 'mp3', 'kuulamine', 'Kuulamine 3 · heli',
      'https://projektid.edu.ee/download/attachments/343705183/B1%20kuulamis%C3%BClesanne%20nr%203.mp3?version=1&modificationDate=1769079738700&api=v2'),
  ('k4', 'pdf', 'kuulamine', 'Kuulamine 4 · ülesanne',
      'https://harno.ee/sites/default/files/documents/2021-06/B1_Ku4_yl_2020.pdf'),
  ('k4a', 'mp3', 'kuulamine', 'Kuulamine 4 · heli',
      'https://projektid.edu.ee/download/attachments/343705183/B1%20kuulamis%C3%BClesanne%20nr%204.mp3?version=1&modificationDate=1769079739330&api=v2'),
  ('kt', 'mp3', 'kuulamine', 'Kuulamistest · täispikk heli',
      'https://projektid.edu.ee/download/attachments/343705183/B1%20kuulamistest.mp3?version=1&modificationDate=1769081405331&api=v2'),
  // lugemine
  ('l1', 'pdf', 'lugemine', 'Lugemine 1 · kuulutused',
      'https://harno.ee/sites/default/files/documents/2021-06/B1_Lu1_kuulutus.pdf'),
  ('l2', 'pdf', 'lugemine', 'Lugemine 2 · valikvastused',
      'https://harno.ee/sites/default/files/documents/2021-06/B1_Lu2Avariant-1_2.pdf'),
  ('l3', 'pdf', 'lugemine', 'Lugemine 3 · lünkülesanne',
      'https://harno.ee/sites/default/files/documents/2021-06/B1_Lu3A_variandid.pdf'),
  ('l4', 'pdf', 'lugemine', 'Lugemine 4 · fraasid',
      'https://harno.ee/sites/default/files/documents/2021-06/B1_Lu4_fraasid.pdf'),
  // rääkimine
  ('r1', 'pdf', 'raakimine', 'Rääkimine 1 · küsimused ja kokkulepe',
      'https://harno.ee/sites/default/files/documents/2021-06/B1_R1_kysimused_kokkulepe.pdf'),
  ('r2', 'pdf', 'raakimine', 'Rääkimine 2 · infovahetus',
      'https://harno.ee/sites/default/files/documents/2021-06/B1_R2_infovahetus.pdf'),
];

Future<void> seedExamAssetsIfEmpty(RadaDb db) async {
  final existing = await db.select(db.examAssets).get();
  if (existing.isNotEmpty) return;
  await db.batch((b) {
    for (final (id, kind, section, title, url) in _examAssetsSeed) {
      b.insert(
        db.examAssets,
        ExamAssetsCompanion.insert(
          id: 'asset-$id',
          kind: kind,
          section: section,
          title: title,
          remoteUrl: url,
        ),
      );
    }
  });
}

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
