import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../data/db.dart';

/// Spec §7 — downloads official exam materials once, checksums them,
/// records local_path. Files live in the app's support directory.
class AssetService {
  final RadaDb db;
  AssetService(this.db);

  Future<String> ensureDownloaded(ExamAsset asset) async {
    if (asset.localPath != null && await File(asset.localPath!).exists()) {
      return asset.localPath!;
    }
    final dir = await getApplicationSupportDirectory();
    final ext = asset.kind == 'mp3' ? 'mp3' : 'pdf';
    final file = File('${dir.path}/exam_assets/${asset.id}.$ext');

    final resp = await http.get(Uri.parse(asset.remoteUrl));
    if (resp.statusCode != 200) {
      throw Exception('Download failed HTTP ${resp.statusCode}');
    }
    await file.create(recursive: true);
    await file.writeAsBytes(resp.bodyBytes);
    final digest = sha256.convert(resp.bodyBytes).toString();

    await (db.update(db.examAssets)..where((a) => a.id.equals(asset.id)))
        .write(ExamAssetsCompanion(
      localPath: Value(file.path),
      sha256: Value(digest),
      updatedAt: Value(DateTime.now()),
    ));
    return file.path;
  }
}
