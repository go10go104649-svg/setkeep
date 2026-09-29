import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/admin/report_repository.dart';
import 'package:setkeep/admin/report_management_page.dart';

class FakeReports implements ReportRepository {
  bool admin = true, fail = false;
  String? rollbackReason;
  final candidates = [
    AdminCandidate({
      'id': 'candidate-1',
      'store_id': 'store',
      'store_name': 'KANEKIN FITNESS GYM 松戸店',
      'equipment_id': 'rack',
      'equipment_name': 'パワーラック',
      'change_type': 'removed',
      'proposed_value': {'equipment_id': 'rack'},
      'status': 'collecting',
      'support_score': 3,
      'oppose_score': 0,
      'unique_reporters': 3,
      'first_seen_at': '2026-09-24T12:34:00Z',
      'last_seen_at': '2026-09-25T12:34:00Z',
    }),
    AdminCandidate({
      'id': 'candidate-2',
      'store_id': 'store',
      'store_name': 'QA店舗',
      'equipment_id': 'machine',
      'equipment_name': 'マシン',
      'change_type': 'removed',
      'proposed_value': {'equipment_id': 'machine'},
      'status': 'auto_applied',
      'support_score': 4,
      'oppose_score': 0,
      'unique_reporters': 4,
      'first_seen_at': '2026-09-24T12:34:00Z',
      'last_seen_at': '2026-09-25T12:34:00Z',
      'applied_at': '2026-09-25T12:35:00Z',
      'before_data': {'presence_status': 'present', 'available': true},
      'after_data': {'presence_status': 'removed', 'available': false},
    }),
    for (final (id, kind, current, proposed) in [
      (
        'quantity',
        'quantity_changed',
        {'quantity': 2},
        {'reported_quantity': 3},
      ),
      (
        'unavailable',
        'temporarily_unavailable',
        {'available': true},
        {'unavailable_scope': 'all'},
      ),
      (
        'recovery',
        'available_again',
        {'available': false, 'unavailable_quantity': 2},
        {'recovery_scope': 'all'},
      ),
    ])
      AdminCandidate({
        'id': 'candidate-$id',
        'store_id': 'store',
        'store_name': 'QA店舗',
        'equipment_id': 'machine',
        'equipment_name': 'マシン',
        'change_type': kind,
        'proposed_value': proposed,
        'current_data': current,
        'status': 'needs_review',
        'support_score': 2,
        'oppose_score': 0,
        'unique_reporters': 2,
        'first_seen_at': '2026-09-24T12:34:00Z',
        'last_seen_at': '2026-09-25T12:34:00Z',
      }),
  ];
  final reports = [
    for (final type in ['exercise', 'equipment'])
      AdminReport({
        'id': type,
        'report_type': type,
        'store_id': 'store',
        'store_name': 'KANEKIN FITNESS GYM 松戸店',
        'target_id': type == 'exercise' ? 'bench_press' : 'rack',
        'equipment_name': type == 'equipment' ? 'パワーラック' : null,
        'entered_name': type == 'equipment' ? '新ラック' : null,
        'report_kind': type == 'exercise' ? 'missing_exercise' : 'added',
        'comment': '確認お願いします',
        'status': 'pending',
        'admin_note': '',
        'created_at': '2026-09-24T12:34:00Z',
      }),
  ];
  @override
  Stream<void> get authChanges => const Stream.empty();
  @override
  Future<bool> isAdmin() async => admin;
  @override
  Future<ReportBatch> list(
    String type,
    String? status,
    String query,
    int offset,
  ) async {
    if (fail) throw StateError('offline');
    final all = reports.where((r) => r.type == type);
    return ReportBatch(
      all
          .where(
            (r) =>
                (status == null || r.status == status) &&
                ('${r.storeName} ${r.targetName}').contains(query),
          )
          .toList(),
      {
        for (final s in reportStatuses.keys)
          s: all.where((r) => r.status == s).length,
      },
    );
  }

  @override
  Future<List<AdminCandidate>> listCandidates(int offset) async {
    if (fail || !admin) throw StateError('denied');
    return candidates.skip(offset).take(50).toList();
  }

  @override
  Future<void> rollbackCandidate(String candidateId, String reason) async {
    if (fail || !admin || reason.trim().isEmpty) throw StateError('denied');
    rollbackReason = reason;
    candidates.firstWhere((c) => c.id == candidateId).data['status'] =
        'rolled_back';
  }

  @override
  Future<void> update(AdminReport r, String status, String note) async {
    if (fail || !admin) throw StateError('denied');
    r.data.addAll({
      'status': status,
      'admin_note': note,
      'reviewed_by': 'admin',
      'reviewed_at': DateTime.now().toIso8601String(),
    });
  }
}

void main() {
  late FakeReports repo;
  setUp(() {
    repo = FakeReports();
    ReportServices.override = repo;
  });
  tearDown(() => ReportServices.override = null);
  testWidgets('regular user cannot see entry or open report management', (
    t,
  ) async {
    repo.admin = false;
    await t.pumpWidget(
      const MaterialApp(home: Scaffold(body: ReportAdminEntry())),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('reportAdminEntry')), findsNothing);
    await t.pumpWidget(const MaterialApp(home: ReportManagementPage()));
    await t.pumpAndSettle();
    expect(find.text('管理者のみ利用できます'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'admin lists reviews and searches both report kinds $platform',
      (t) async {
        await t.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: const Scaffold(body: ReportAdminEntry()),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('reportAdminEntry')));
        await t.pumpAndSettle();
        expect(find.textContaining('KANEKIN FITNESS GYM 松戸店'), findsOneWidget);
        expect(find.textContaining('ベンチプレス'), findsOneWidget);
        expect(find.text('未確認 1'), findsOneWidget);
        await t.tap(find.byKey(const Key('adminReportexercise')));
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('reportAdminNote')), '確認します');
        await t.ensureVisible(find.byKey(const Key('startReportReview')));
        await t.tap(find.byKey(const Key('startReportReview')));
        await t.pumpAndSettle();
        expect(repo.reports.first.status, 'reviewing');
        await t.tap(find.byKey(const Key('reportStatusreviewing')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('adminReportexercise')));
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const Key('applyReportReview')));
        await t.tap(find.byKey(const Key('applyReportReview')));
        await t.pumpAndSettle();
        expect(repo.reports.first.status, 'reviewing');
        await t.tap(find.byKey(const Key('confirmReportReview')));
        await t.pumpAndSettle();
        expect(repo.reports.first.status, 'applied');
        expect(repo.reports.first.note, '確認します');
        await t.tap(find.text('設備情報'));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('reportStatuspending')));
        await t.pumpAndSettle();
        expect(find.textContaining('パワーラック'), findsOneWidget);
        await t.enterText(find.byKey(const Key('reportAdminSearch')), '存在しない');
        await t.pumpAndSettle(const Duration(milliseconds: 400));
        expect(find.text('報告はありません'), findsOneWidget);
        await t.enterText(find.byKey(const Key('reportAdminSearch')), '');
        await t.pumpAndSettle(const Duration(milliseconds: 400));
        await t.tap(find.byKey(const Key('adminReportequipment')));
        await t.pumpAndSettle();
        expect(find.textContaining('新ラック'), findsOneWidget);
        await t.ensureVisible(find.byKey(const Key('rejectReportReview')));
        await t.tap(find.byKey(const Key('rejectReportReview')));
        await t.pumpAndSettle();
        expect(find.text('却下理由を管理者メモに入力してください'), findsOneWidget);
        await t.enterText(
          find.byKey(const Key('reportAdminNote')),
          '確認できませんでした',
        );
        await t.ensureVisible(find.byKey(const Key('rejectReportReview')));
        await t.tap(find.byKey(const Key('rejectReportReview')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('confirmReportReview')));
        await t.pumpAndSettle();
        expect(repo.reports.last.status, 'rejected');
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('report loading error can retry', (t) async {
    repo.fail = true;
    await t.pumpWidget(const MaterialApp(home: ReportManagementPage()));
    await t.pumpAndSettle();
    expect(find.textContaining('報告を取得できません'), findsOneWidget);
    repo.fail = false;
    await t.tap(find.byTooltip('再読み込み'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('adminReportexercise')), findsOneWidget);
  });
  testWidgets(
    'admin sees candidate decision without changing report workflow',
    (t) async {
      await t.pumpWidget(const MaterialApp(home: ReportManagementPage()));
      await t.pumpAndSettle();
      await t.tap(find.text('変更候補'));
      await t.pumpAndSettle();
      expect(
        find.byKey(const Key('adminCandidatecandidate-1')),
        findsOneWidget,
      );
      expect(find.textContaining('情報収集中'), findsOneWidget);
      expect(find.textContaining('支持 3 / 反対 0'), findsOneWidget);
      expect(find.textContaining('報告者 3人'), findsOneWidget);
      expect(find.textContaining('初回 2026/'), findsWidgets);
      expect(find.textContaining('最終 2026/'), findsWidgets);
      await t.tap(find.text('設備情報'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('adminReportequipment')), findsOneWidget);
    },
  );
  testWidgets('admin sees current and proposed equipment state', (t) async {
    await t.pumpWidget(const MaterialApp(home: ReportManagementPage()));
    await t.pumpAndSettle();
    await t.tap(find.text('変更候補'));
    await t.pumpAndSettle();
    expect(find.textContaining('現在値: 2台 → 変更候補: 3台'), findsOneWidget);
    expect(find.textContaining('現在: 利用可能 → 候補: 一時利用不可'), findsOneWidget);
    expect(find.textContaining('現在: 一時利用不可 → 候補: 利用可能（全台復旧）'), findsOneWidget);
  });
  testWidgets(
    'auto-applied candidate requires a reason and confirms rollback',
    (t) async {
      await t.pumpWidget(const MaterialApp(home: ReportManagementPage()));
      await t.pumpAndSettle();
      await t.tap(find.text('変更候補'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('adminCandidatecandidate-2')));
      await t.pumpAndSettle();
      expect(find.textContaining('反映日時'), findsOneWidget);
      expect(find.text('変更前'), findsOneWidget);
      expect(find.text('変更後'), findsOneWidget);
      await t.tap(find.byKey(const Key('rollbackCandidate')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(
              find.byKey(const Key('confirmCandidateRollback')),
            )
            .onPressed,
        isNull,
      );
      await t.enterText(
        find.byKey(const Key('candidateRollbackReason')),
        '設備の撤去情報に誤り',
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('confirmCandidateRollback')));
      await t.pumpAndSettle();
      expect(repo.rollbackReason, '設備の撤去情報に誤り');
      expect(repo.candidates.firstWhere((c) => c.id == 'candidate-2').status, 'rolled_back');
    },
  );
}
