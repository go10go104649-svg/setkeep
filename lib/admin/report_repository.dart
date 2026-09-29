import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../exercise_form_catalog.dart';

const reportStatuses = {
  'pending': '未確認',
  'reviewing': '確認中',
  'applied': '反映済み',
  'rejected': '却下',
};
const reportKinds = {
  'store_temporarily_closed': '一時休業している',
  'store_reopened': '営業再開している',
  'store_closed': '閉店している',
  'store_new_store': '掲載されていない店舗',
  'store_relocated': '移転している',
  'store_wrong_name': '店舗名が違う',
  'store_wrong_address': '住所が違う',
  'store_other': 'その他の店舗情報',
  'missing_exercise': 'できるのに表示されていない',
  'incorrect_exercise': '表示されているができない',
  'not_present': '設置されていない',
  'removed': '撤去された',
  'added': '新しく追加された',
  'quantity_changed': '台数が違う',
  'temporarily_unavailable': '現在利用できない',
  'available_again': '利用可能に戻った',
  'wrong_name': '名称が違う',
  'other': 'その他',
};
const candidateStatuses = {
  'collecting': '情報収集中',
  'needs_review': '管理者確認が必要',
  'auto_ready': '自動反映条件を達成',
  'auto_applied': '自動反映済み',
  'admin_applied': '管理者反映済み',
  'rejected': '却下',
  'expired': '期限切れ',
  'superseded': '更新済み',
  'rolled_back': '差し戻し',
};

class AdminCandidate {
  AdminCandidate(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get status => data['status'] as String;
  String get statusLabel => candidateStatuses[status] ?? status;
  bool get isStore => data['entity_type'] == 'store';
  String get changeType => data['change_type'] as String;
  String get changeLabel => reportKinds[changeType] ?? changeType;
  String get storeName =>
      data['store_name'] as String? ?? data['store_id'] as String? ?? '新店舗';
  String get targetName {
    final proposed = Map<String, dynamic>.from(
      data['proposed_value'] as Map? ?? {},
    );
    if (isStore) return proposed['name'] as String? ?? '店舗の営業情報';
    return proposed['equipment_name'] as String? ??
        data['equipment_name'] as String? ??
        data['equipment_id'] as String? ??
        '設備指定なし';
  }

  num get supportScore => data['support_score'] as num;
  num get opposeScore => data['oppose_score'] as num;
  int get uniqueReporters => data['unique_reporters'] as int;
  DateTime? get appliedAt =>
      DateTime.tryParse(data['applied_at'] as String? ?? '');
  Map<String, dynamic>? get beforeData => data['before_data'] is Map
      ? Map<String, dynamic>.from(data['before_data'] as Map)
      : null;
  Map<String, dynamic>? get afterData => data['after_data'] is Map
      ? Map<String, dynamic>.from(data['after_data'] as Map)
      : null;
  Map<String, dynamic>? get currentData => data['current_data'] is Map
      ? Map<String, dynamic>.from(data['current_data'] as Map)
      : null;
  Map<String, dynamic> get proposedValue =>
      Map<String, dynamic>.from(data['proposed_value'] as Map? ?? {});
  String? get stateSummary {
    final current = beforeData ?? currentData;
    if (isStore) {
      return '現在: ${currentData?['operational_status'] ?? current?['operational_status'] ?? '未登録'} → 候補: ${proposedValue['operational_status'] ?? proposedValue['name'] ?? proposedValue['address'] ?? '管理者確認'}';
    }
    if (changeType == 'quantity_changed') {
      return '現在値: ${current?['quantity'] ?? '不明'}台 → 変更候補: ${proposedValue['reported_quantity']}台';
    }
    if (changeType == 'temporarily_unavailable' ||
        changeType == 'available_again') {
      String status(Map<String, dynamic>? row) {
        if (row == null) return '不明';
        if (row['available'] == false) return '一時利用不可';
        final unavailable = row['unavailable_quantity'] as num?;
        if (unavailable != null && unavailable > 0) {
          return '${unavailable.toInt()}台利用不可';
        }
        return '利用可能';
      }

      final proposed = changeType == 'available_again'
          ? '利用可能（全台復旧）'
          : proposedValue['unavailable_scope'] == 'partial'
          ? '${proposedValue['reported_unavailable_quantity']}台利用不可'
          : '一時利用不可';
      return '現在: ${status(current)} → 候補: $proposed';
    }
    return null;
  }

  String dateLabel(String field) {
    final d = DateTime.parse(data[field] as String).toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${pad(d.month)}/${pad(d.day)} ${pad(d.hour)}:${pad(d.minute)}';
  }
}

class AdminReport {
  AdminReport(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get type => data['report_type'] as String;
  String get status => data['status'] as String;
  String get storeId => data['store_id'] as String;
  String get storeName => data['store_name'] as String;
  String get targetName => type == 'exercise'
      ? ExerciseFormCatalog.canonicalDefinition(
              data['target_id'] as String? ?? '',
            )?.exerciseName ??
            data['target_id'] as String? ??
            '対象指定なし'
      : data['equipment_name'] as String? ??
            data['entered_name'] as String? ??
            '対象指定なし';
  String get kindLabel => reportKinds[data['report_kind']] ?? 'その他';
  String get note => data['admin_note'] as String? ?? '';
  String get dateLabel {
    final d = DateTime.parse(data['created_at'] as String).toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${pad(d.month)}/${pad(d.day)} ${pad(d.hour)}:${pad(d.minute)}';
  }
}

class ReportBatch {
  const ReportBatch(this.rows, this.counts);
  final List<AdminReport> rows;
  final Map<String, int> counts;
}

abstract class ReportRepository {
  Future<bool> isAdmin();
  Stream<void> get authChanges;
  Future<ReportBatch> list(
    String type,
    String? status,
    String query,
    int offset,
  );
  Future<List<AdminCandidate>> listCandidates(
    int offset, {
    String entityType = 'store_equipment',
  });
  Future<List<Map<String, dynamic>>> candidateEvidence(String id);
  Future<void> reviewStoreCandidate(String id, String action, String note);
  Future<void> rollbackCandidate(String candidateId, String reason);
  Future<void> update(AdminReport report, String status, String note);
}

class ReportServices {
  static ReportRepository? override;
  static ReportRepository get repository =>
      override ?? SupabaseReportRepository();
}

class SupabaseReportRepository implements ReportRepository {
  SupabaseClient get client => Supabase.instance.client;
  @override
  Stream<void> get authChanges => SupabaseConfig.initialized
      ? client.auth.onAuthStateChange.map((_) {})
      : const Stream.empty();
  @override
  Future<bool> isAdmin() async {
    if (!SupabaseConfig.initialized || client.auth.currentUser == null) {
      return false;
    }
    return await client.rpc('is_report_admin') == true;
  }

  @override
  Future<ReportBatch> list(
    String type,
    String? status,
    String query,
    int offset,
  ) async {
    final q = query.trim().toLowerCase();
    final ids = ExerciseFormCatalog.entries
        .where(
          (e) => '${e.exerciseName} ${e.englishName} ${e.aliases.join(' ')}'
              .toLowerCase()
              .contains(q),
        )
        .map((e) => e.exerciseId)
        .toList();
    final result = Map<String, dynamic>.from(
      await client.rpc(
        'list_admin_reports',
        params: {
          'report_type_filter': type,
          'status_filter': status,
          'search_text': query.trim(),
          'exercise_ids': q.isEmpty ? <String>[] : ids,
          'page_offset': offset,
        },
      ) as Map,
    );
    return ReportBatch(
      (result['rows'] as List)
          .map((r) => AdminReport(Map<String, dynamic>.from(r as Map)))
          .toList(),
      Map<String, int>.from(result['counts'] as Map? ?? {}),
    );
  }

  @override
  Future<List<AdminCandidate>> listCandidates(
    int offset, {
    String entityType = 'store_equipment',
  }) async {
    final rows = await client
        .from('admin_gym_change_candidates')
        .select()
        .eq('entity_type', entityType)
        .order('last_seen_at', ascending: false)
        .range(offset, offset + 49);
    return rows
        .map((row) => AdminCandidate(Map<String, dynamic>.from(row)))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> candidateEvidence(String id) async {
    return await client
        .from('gym_change_evidence')
        .select()
        .eq('candidate_id', id)
        .order('observed_at', ascending: false)
        .limit(100);
  }

  @override
  Future<void> reviewStoreCandidate(
    String id,
    String action,
    String note,
  ) async {
    await client.rpc(
      'review_gym_store_candidate',
      params: {'target_id': id, 'action': action, 'note': note},
    );
  }

  @override
  Future<void> rollbackCandidate(String candidateId, String reason) async {
    await client.rpc(
      'rollback_gym_change_candidate',
      params: {'target_id': candidateId, 'reason': reason},
    );
  }

  @override
  Future<void> update(AdminReport report, String status, String note) async {
    await client.rpc(
      'update_admin_report',
      params: {
        'report_type_value': report.type,
        'report_id': report.id,
        'expected_status': report.status,
        'new_status': status,
        'note': note.trim(),
      },
    );
  }
}
