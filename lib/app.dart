import 'package:flutter/material.dart';

import 'data/db.dart';
import 'data/repo.dart';
import 'features/trail/trail_screen.dart';
import 'theme/themes.dart';
import 'theme/tokens.dart';

class RadaApp extends StatefulWidget {
  final RadaDb db;
  final bool syncConfigured;
  final String? initialThemeName;
  const RadaApp({
    super.key,
    required this.db,
    required this.syncConfigured,
    this.initialThemeName,
  });

  @override
  State<RadaApp> createState() => _RadaAppState();
}

class _RadaAppState extends State<RadaApp> {
  late RadaTokens _tokens = allThemes.firstWhere(
    (t) => t.name == widget.initialThemeName,
    orElse: () => vaikus,
  );
  late bool _syncConfigured = widget.syncConfigured;

  void _setTheme(RadaTokens t) {
    setState(() => _tokens = t);
    Repo(widget.db).setSetting('theme', t.name); // persist (B6)
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rada',
      debugShowCheckedModeBanner: false,
      theme: _tokens.toThemeData(),
      home: TrailScreen(
        db: widget.db,
        tokens: _tokens,
        syncConfigured: _syncConfigured,
        onThemeChanged: _setTheme,
        onSyncConfigured: (v) => setState(() => _syncConfigured = v),
      ),
    );
  }
}
