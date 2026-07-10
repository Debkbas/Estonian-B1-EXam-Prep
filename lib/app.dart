import 'package:flutter/material.dart';

import 'data/db.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'theme/themes.dart';
import 'theme/tokens.dart';

class RadaApp extends StatefulWidget {
  final RadaDb db;
  final bool syncConfigured;
  const RadaApp({super.key, required this.db, required this.syncConfigured});

  @override
  State<RadaApp> createState() => _RadaAppState();
}

class _RadaAppState extends State<RadaApp> {
  RadaTokens _tokens = vaikus;

  void _setTheme(RadaTokens t) => setState(() => _tokens = t);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rada',
      debugShowCheckedModeBanner: false,
      theme: _tokens.toThemeData(),
      home: DashboardScreen(
        db: widget.db,
        tokens: _tokens,
        syncConfigured: widget.syncConfigured,
        onThemeChanged: _setTheme,
      ),
    );
  }
}
