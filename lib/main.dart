import 'package:flutter/material.dart';

import 'app.dart';
import 'data/db.dart';
import 'data/repo.dart';
import 'data/seed_loader.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = RadaDb();
  await seedSyllabusIfEmpty(db);
  await seedExamAssetsIfEmpty(db);

  final repo = Repo(db);
  final syncConfigured = await initSupabaseFromSettings(repo);
  final themeName = await repo.getSetting('theme');

  runApp(RadaApp(
    db: db,
    syncConfigured: syncConfigured,
    initialThemeName: themeName,
  ));
}
