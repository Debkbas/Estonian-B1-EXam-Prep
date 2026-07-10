import 'package:supabase_flutter/supabase_flutter.dart';

/// Spec §9 — Supabase courier, local-first. M0 scope: prove round-trip with
/// the sync_probe table. Full outbox/LWW reconciliation lands with M1.
class SyncService {
  final SupabaseClient _client;
  final String deviceId;

  SyncService(this._client, {required this.deviceId});

  Future<void> pushProbe(String message) async {
    await _client.from('sync_probe').insert({
      'message': message,
      'device_id': deviceId,
    });
  }

  Future<List<Map<String, dynamic>>> fetchProbes() async {
    final rows = await _client
        .from('sync_probe')
        .select()
        .order('created_at', ascending: false)
        .limit(20);
    return List<Map<String, dynamic>>.from(rows);
  }
}
