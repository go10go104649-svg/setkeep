import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/gym/gym_repository.dart';
import 'package:setkeep/gym/gym_pages.dart';
import 'package:setkeep/gym/store_report_sheet.dart';
import 'package:setkeep/gym/training_place_preference.dart';
import 'package:setkeep/admin/report_repository.dart';
import 'package:setkeep/admin/report_management_page.dart';

import 'gym_integration_test.dart' show FakeGyms;
import 'report_management_test.dart' show FakeReports;

GymStore store(String status) => GymStore(
  id: 'lifecycle',
  chainName: 'QA',
  name: '店舗',
  chainId: 'qa',
  active: status != 'closed',
  operationalStatus: status,
);

class StoreRepo extends FakeGyms {
  final sent = <Map<String, Object?>>[];
  bool sendFails = false;
  @override
  Future<List<GymStore>> search(String q, {int offset = 0}) async => saved;
  @override
  Future<void> reportStore({
    String? storeId,
    String? chainId,
    String? chainName,
    required String kind,
    String? name,
    String? address,
    String? officialUrl,
    required String comment,
  }) async {
    if (sendFails) throw StateError('network');
    sent.add({
      'store_id': storeId,
      'kind': kind,
      'name': name,
      'address': address,
      'chain': chainName,
    });
  }
}

void main() {
  late StoreRepo repo;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = StoreRepo();
    GymServices.override = repo;
  });
  tearDown(() {
    GymServices.override = null;
    ReportServices.override = null;
  });
  test('statuses roundtrip and legacy preopening retain selection policy', () {
    for (final status in [
      'active',
      'preopening',
      'temporarily_closed',
      'closed',
      'unknown',
    ]) {
      final s = GymStore.fromJson(store(status).toJson());
      expect(s.effectiveStatus, status);
      expect(s.isSelectable, status == 'active');
    }
    expect(
      GymStore.fromJson({
        'id': 'x',
        'name': '旧店舗',
        'source': {'page_status': 'preopening_text'},
      }).isSelectable,
      isFalse,
    );
  });
  for (final status in ['temporarily_closed', 'closed']) {
    test(
      'unavailable default is preserved while new workout falls back $status',
      () async {
        await TrainingPlacePreference.save(
          TrainingPlace.store(store('active')),
        );
        repo.saved = [store(status)];
        final resolved = await TrainingPlacePreference.forNewWorkout();
        expect(resolved.isHome, isTrue);
        expect(resolved.notice, contains(store(status).statusLabel));
        expect((await TrainingPlacePreference.load()).storeId, 'lifecycle');
        expect(
          (await TrainingPlacePreference.reconcile(repo.saved)).storeId,
          'lifecycle',
        );
        repo.saved = [store('active')];
        expect(
          (await TrainingPlacePreference.forNewWorkout()).storeId,
          'lifecycle',
        );
      },
    );
  }
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('store reporting entry leaves room for keyboard $platform', (
      t,
    ) async {
      repo.saved = [store('active')];
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: const GymStoreSearchPage(),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('gymStoreSearchField')));
      t.view.viewInsets = const FakeViewPadding(bottom: 280);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byType(ListView)).height, greaterThan(60));
    });
    testWidgets(
      'temporary closure searchable and disabled in detail $platform',
      (t) async {
        repo.saved = [store('temporarily_closed')];
        t.view.physicalSize = const Size(360, 740);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: const GymStoreSearchPage(),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('一時休業中'), findsOneWidget);
        await t.tap(find.byKey(const Key('selectGymStorelifecycle')));
        await t.pumpAndSettle();
        expect(find.textContaining('一時休業中。現在の利用場所'), findsOneWidget);
        expect(
          t
              .widget<FilledButton>(
                find.byKey(const Key('confirmGymStoreSelection')),
              )
              .onPressed,
          isNull,
        );
        expect(find.byKey(const Key('reportGymStore')), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'store report validates fields, survives failure and sends once',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showGymStoreReport(context, store: store('active')),
                child: const Text('報告'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('報告'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('storeReportKind')));
      await t.pumpAndSettle();
      await t.tap(find.text('住所が違う').last);
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('submitStoreReport')))
            .onPressed,
        isNull,
      );
      await t.enterText(find.byKey(const Key('storeReportAddress')), '正しい住所');
      await t.pump();
      repo.sendFails = true;
      await t.ensureVisible(find.byKey(const Key('submitStoreReport')));
      await t.tap(find.byKey(const Key('submitStoreReport')));
      await t.pumpAndSettle();
      expect(find.textContaining('報告を送信できませんでした'), findsOneWidget);
      repo.sendFails = false;
      await t.tap(find.byKey(const Key('submitStoreReport')));
      await t.pumpAndSettle();
      expect(repo.sent.single['kind'], 'wrong_address');
      expect(repo.sent.single['store_id'], 'lifecycle');
      expect(find.textContaining('店舗情報の報告を受け付けました'), findsOneWidget);
    },
  );
  testWidgets('new store request separate from private place registration', (
    t,
  ) async {
    await t.pumpWidget(const MaterialApp(home: GymStoreSearchPage()));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('reportMissingStore')));
    await t.pumpAndSettle();
    expect(
      t
          .widget<FilledButton>(find.byKey(const Key('submitStoreReport')))
          .onPressed,
      isNull,
    );
    await t.enterText(find.byKey(const Key('storeReportChain')), '新チェーン');
    await t.enterText(find.byKey(const Key('storeReportName')), '新店舗');
    await t.enterText(find.byKey(const Key('storeReportAddress')), '東京都');
    await t.pump();
    await t.ensureVisible(find.byKey(const Key('submitStoreReport')));
    await t.tap(find.byKey(const Key('submitStoreReport')));
    await t.pumpAndSettle();
    expect(repo.sent.single['kind'], 'new_store');
    expect(repo.sent.single['store_id'], isNull);
    expect(repo.saved, isEmpty);
  });
  testWidgets('admin store queue supports reason-required manual closure', (
    t,
  ) async {
    final admin = FakeReports();
    ReportServices.override = admin;
    admin.candidates.add(
      AdminCandidate({
        'id': 'store-candidate',
        'entity_type': 'store',
        'store_id': 'lifecycle',
        'store_name': 'QA店舗',
        'change_type': 'store_closed',
        'status': 'needs_review',
        'support_score': 4,
        'oppose_score': 0,
        'unique_reporters': 4,
        'first_seen_at': '2026-09-29T00:00:00Z',
        'last_seen_at': '2026-09-29T00:00:00Z',
        'current_data': {'operational_status': 'active'},
        'proposed_value': {'operational_status': 'closed'},
        'evidence_count': 4,
      }),
    );
    await t.pumpWidget(const MaterialApp(home: ReportManagementPage()));
    await t.pumpAndSettle();
    await t.tap(find.text('店舗情報'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('adminCandidatestore-candidate')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('applyStoreCandidate')));
    await t.tap(find.byKey(const Key('applyStoreCandidate')));
    await t.pumpAndSettle();
    expect(
      t
          .widget<FilledButton>(find.byKey(const Key('confirmStoreCandidate')))
          .onPressed,
      isNull,
    );
    await t.enterText(find.byKey(const Key('storeCandidateNote')), '公式案内を確認');
    await t.pump();
    await t.tap(find.byKey(const Key('confirmStoreCandidate')));
    await t.pumpAndSettle();
    expect(admin.candidates.last.status, 'admin_applied');
    expect(t.takeException(), isNull);
  });
}
