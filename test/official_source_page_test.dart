import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/admin/official_source_page.dart';
import 'package:setkeep/admin/official_source_repository.dart';

class FakeOfficialSources implements OfficialSourceRepository {
  bool admin = true, fail = false;
  int reads = 0, marks = 0;
  final changes = StreamController<void>.broadcast();
  @override
  Stream<void> get authChanges => changes.stream;
  @override
  Future<bool> isAdmin() async => admin;
  @override
  Future<List<Map<String, dynamic>>> sources(int offset) async {
    reads++;
    if (fail) throw StateError('offline');
    return [
      {
        'id': 'source',
        'url': 'https://www.anytimefitness.co.jp/qa/',
        'gym_stores': {'name': 'QA店'},
        'gym_chains': {'name': 'Anytime'},
        'status': 'manual_review',
        'enabled': false,
        'policy_status': 'needs_review',
        'policy_note': '利用条件確認待ち',
        'current_data': {'equipment': []},
        'last_error': 'parse_error: layout changed',
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> snapshots(String id) async => [
    {
      'fetched_at': '2026-09-29T00:00:00Z',
      'http_status': 200,
      'is_changed': true,
      'parser_version': 'anytime-1',
      'gym_official_snapshot_candidates': [
        {'candidate_id': 'candidate'},
      ],
    },
  ];
  @override
  Future<void> markForReview(String id) async {
    marks++;
  }
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('source details fit a narrow screen on $platform', (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repo = FakeOfficialSources();
      addTearDown(repo.changes.close);
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: OfficialSourcePage(repository: repo),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Anytime QA店'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('再確認対象にする'));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('nonadmin cannot fetch or display sources', (t) async {
    final repo = FakeOfficialSources()..admin = false;
    addTearDown(repo.changes.close);
    await t.pumpWidget(MaterialApp(home: OfficialSourcePage(repository: repo)));
    await t.pumpAndSettle();
    expect(find.text('管理者のみ利用できます'), findsOneWidget);
    expect(repo.reads, 0);
  });
  testWidgets(
    'admin sees disabled policy, results and audit; mark does not fetch',
    (t) async {
      final repo = FakeOfficialSources();
      addTearDown(repo.changes.close);
      await t.pumpWidget(
        MaterialApp(home: OfficialSourcePage(repository: repo)),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('定期取得無効'), findsOneWidget);
      await t.tap(find.text('Anytime QA店'));
      await t.pumpAndSettle();
      expect(find.text('利用条件確認待ち'), findsOneWidget);
      expect(find.text('parse_error: layout changed'), findsOneWidget);
      await t.ensureVisible(find.text('再確認対象にする'));
      await t.tap(find.text('再確認対象にする'));
      await t.pumpAndSettle();
      expect(repo.marks, 1);
      expect(repo.reads, 1);
      expect(find.text('再確認対象にしました（取得は開始しません）'), findsOneWidget);
      repo.admin = false;
      repo.changes.add(null);
      await t.pumpAndSettle();
      expect(find.text('Anytime QA店'), findsNothing);
    },
  );
  testWidgets('network error retries without exposing stale data', (t) async {
    final repo = FakeOfficialSources()..fail = true;
    addTearDown(repo.changes.close);
    await t.pumpWidget(MaterialApp(home: OfficialSourcePage(repository: repo)));
    await t.pumpAndSettle();
    expect(find.textContaining('取得できませんでした'), findsOneWidget);
    repo.fail = false;
    await t.tap(find.byTooltip('再読み込み'));
    await t.pumpAndSettle();
    expect(find.text('Anytime QA店'), findsOneWidget);
  });
}
