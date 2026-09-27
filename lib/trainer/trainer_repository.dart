import 'tenant_repository.dart';

import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared boundary used by both apps. Trainer identity is always server-derived.
class TrainerRepository {
  TrainerRepository(this.client);
  final SupabaseClient client;
  TrainerRepository forTenant(String tenantId) =>
      TenantRepository(client, tenantId);
  String get userId => client.auth.currentUser!.id;
  Future<Map<String, dynamic>?> profile() => client
      .from('trainer_profiles')
      .select()
      .eq('user_id', userId)
      .maybeSingle();
  Future<void> saveProfile(String name) => client
      .from('trainer_profiles')
      .upsert({'user_id': userId, 'display_name': name.trim()});
  Future<List<Map<String, dynamic>>> clients() => client
      .from('trainer_client_links')
      .select()
      .eq('trainer_id', userId)
      .eq('status', 'active')
      .order('client_name');
  Future<List<Map<String, dynamic>>> myLinks() async =>
      List<Map<String, dynamic>>.from(
        await client.rpc('tenant_my_links') as List,
      );
  Future<List<Map<String, dynamic>>> tenants() =>
      client.from('tenants').select().order('created_at');
  Future<String> createTenant(String name, String kind) async =>
      await client.rpc(
        'tenant_create',
        params: {'p_name': name.trim(), 'p_kind': kind},
      ) as String;
  Future<String> createInvite() async =>
      await client.rpc('trainer_create_invite') as String;
  Future<String?> previewInvite(String token) async =>
      await client.rpc('trainer_preview_invite', params: {'p_token': token})
          as String?;
  Future<void> acceptInvite(
    String token,
    String name, {
    required bool recording,
    required bool heatmap,
  }) async {
    await client.rpc(
      'trainer_accept_invite',
      params: {
        'p_token': token,
        'p_name': name.trim(),
        'p_recording': recording,
        'p_heatmap': heatmap,
      },
    );
  }

  Future<void> revoke(String link) async =>
      client.rpc('trainer_revoke_link', params: {'p_link': link});
  Future<List<Map<String, dynamic>>> workouts(
    String clientId, {
    int offset = 0,
  }) async => List<Map<String, dynamic>>.from(
    await client.rpc(
      'trainer_client_workouts',
      params: {'p_client': clientId, 'p_offset': offset},
    ) as List,
  );
  Future<List<Map<String, dynamic>>> notes(String clientId) => client
      .from('trainer_notes')
      .select()
      .eq('trainer_id', userId)
      .eq('client_id', clientId)
      .order('created_at', ascending: false);
  Future<void> addNote(String clientId, String body) => client
      .from('trainer_notes')
      .insert({'client_id': clientId, 'body': body.trim()});
  Future<List<Map<String, dynamic>>> menus({String? clientId}) {
    var query = client.from('trainer_menus').select().eq('trainer_id', userId);
    if (clientId != null) query = query.eq('client_id', clientId);
    return query.order('created_at', ascending: false);
  }

  Future<void> addMenu(
    String clientId,
    String name,
    String note,
    List<Map<String, dynamic>> items,
  ) => client.from('trainer_menus').insert({
    'client_id': clientId,
    'name': name.trim(),
    'note': note.trim(),
    'items': items,
  });
  Future<void> recordWorkout(
    String clientId,
    String requestId,
    DateTime date,
    List<Map<String, dynamic>> sets, {
    String note = '',
  }) async {
    if (note.trim().isNotEmpty) {
      throw UnsupportedError('Session comments require a tenant repository');
    }
    await client.rpc(
      'trainer_record_workout',
      params: {
        'p_client': clientId,
        'p_request': requestId,
        'p_date': date.toUtc().toIso8601String(),
        'p_sets': sets,
      },
    );
  }

  Future<void> shareWorkout(Map<String, dynamic> workout) async {
    await client.rpc(
      'trainer_share_workout',
      params: {
        'p_date': workout['date'],
        'p_duration': workout['durationSeconds'] ?? 0,
        'p_gym': workout['gymName'],
        'p_sets': workout['sets'],
      },
    );
  }

  Future<List<Map<String, dynamic>>> recordedForMe({int offset = 0}) => client
      .from('workouts')
      .select('id,performed_at,duration_seconds,gym_name,note,sets,canceled_at')
      .eq('user_id', userId)
      .eq('record_source', 'trainer')
      .order('performed_at')
      .order('id')
      .range(offset, offset + 99);
  // Owner mutations persist before the caller offers Undo. Attribution and
  // trainer audit rows stay intact; deletion is a server-side cancellation.
  Future<void> deleteRecordedWorkout(String id) => client.rpc(
    'owner_mutate_recorded_workout',
    params: {'p_record': id, 'p_action': 'delete'},
  );
  Future<void> restoreRecordedWorkout(String id) => client.rpc(
    'owner_mutate_recorded_workout',
    params: {'p_record': id, 'p_action': 'restore'},
  );
  Future<void> updateRecordedWorkout(
    String id,
    List<Map<String, dynamic>> sets,
  ) => client.rpc(
    'owner_mutate_recorded_workout',
    params: {'p_record': id, 'p_action': 'update', 'p_sets': sets},
  );

  static String requestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
