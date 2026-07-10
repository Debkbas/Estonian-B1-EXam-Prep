import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'data/db.dart';
import 'data/seed_loader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env is optional in M0 — the app runs without Supabase configured.
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}

  final supabaseUrl = dotenv.maybeGet('SUPABASE_URL');
  final supabaseKey = dotenv.maybeGet('SUPABASE_ANON_KEY');
  final syncConfigured =
      (supabaseUrl?.isNotEmpty ?? false) && (supabaseKey?.isNotEmpty ?? false);
  if (syncConfigured) {
    await Supabase.initialize(url: supabaseUrl!, publishableKey: supabaseKey!);
  }

  final db = RadaDb();
  await seedSyllabusIfEmpty(db);
  await seedExamAssetsIfEmpty(db);

  runApp(RadaApp(db: db, syncConfigured: syncConfigured));
}
