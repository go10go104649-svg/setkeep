import 'package:supabase_flutter/supabase_flutter.dart';

import 'report_repository.dart';

abstract class OfficialSourceRepository {
  Future<bool> isAdmin();
  Stream<void> get authChanges;
  Future<List<Map<String, dynamic>>> sources(int offset);
  Future<List<Map<String, dynamic>>> snapshots(String sourceId);
  Future<void> markForReview(String sourceId);
}

class SupabaseOfficialSourceRepository implements OfficialSourceRepository {
  SupabaseClient get client => Supabase.instance.client;
  @override
  Future<bool> isAdmin() => ReportServices.repository.isAdmin();
  @override
  Stream<void> get authChanges => ReportServices.repository.authChanges;
  @override
  Future<List<Map<String, dynamic>>> sources(int offset) async =>
      List<Map<String, dynamic>>.from(
        await client
            .from('gym_official_sources')
            .select('*,gym_stores(name),gym_chains(name)')
            .order('url')
            .range(offset, offset + 49),
      );
  @override
  Future<List<Map<String, dynamic>>> snapshots(String sourceId) async =>
      List<Map<String, dynamic>>.from(
        await client
            .from('gym_official_source_snapshots')
            .select('*,gym_official_snapshot_candidates(candidate_id)')
            .eq('source_id', sourceId)
            .order('fetched_at', ascending: false)
            .limit(10),
      );
  @override
  Future<void> markForReview(String sourceId) async {
    await client.rpc(
      'mark_official_source_for_review',
      params: {'target_id': sourceId},
    );
  }
}

String officialDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return '未取得';
  final local = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String officialStatus(dynamic value) => switch (value) {
  'ok' => '取得成功',
  'pending' => '取得待ち',
  'fetch_error' => '取得エラー',
  'source_broken' => '参照先の確認が必要',
  'manual_review' => '管理者確認が必要',
  _ => '未取得',
};
