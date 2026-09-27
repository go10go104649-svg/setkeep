import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/trainer/tenant_repository.dart';
import 'package:setkeep_trainer/main.dart';
import 'package:setkeep_trainer/tenant_management.dart';

import 'trainer_app_test.dart' show FakeAuth, FakeRepository, link, menuFixture;

class UiRepository extends FakeRepository {
  final commentRows = <Map<String, dynamic>>[];
  @override
  Future<List<Map<String, dynamic>>> notes(String clientId) async =>
      commentRows;
}

class ManagementRepository extends FakeRepository implements TenantRepository {
  @override
  Future<List<Map<String, dynamic>>> members() async => [
    {
      'user_id': 'trainer-id',
      'display_name': 'Coach',
      'status': 'active',
      'is_admin': true,
      'is_trainer': true,
    },
  ];
  @override
  Future<List<Map<String, dynamic>>> assignments() async => [];
  @override
  Future<Map<String, dynamic>> billing() async => {
    'status': 'active',
    'active_trainers': 1,
    'monthly_jpy': 3980,
  };
}

void main() {
  testWidgets(
    'HOME and clients have distinct roles with searchable client cards',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final auth = FakeAuth();
      addTearDown(auth.events.close);
      final repo = UiRepository()
        ..links.addAll([
          {...link(), 'client_name': 'Alice'},
          {...link(), 'client_name': 'Bob', 'client_id': 'bob'},
        ]);
      await t.pumpWidget(TrainerApp(auth: auth, repository: repo));
      await t.pumpAndSettle();
      expect(find.text('Quick actions'), findsOneWidget);
      expect(find.byKey(const Key('clientSearchField')), findsNothing);
      await t.tap(find.text('Clients'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('clientSearchField')), findsOneWidget);
      await t.enterText(find.byKey(const Key('clientSearchField')), 'Bob');
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Bob'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      await t.tap(find.widgetWithText(ListTile, 'Bob'));
      await t.pumpAndSettle();
      expect(find.byType(ClientPage), findsOneWidget);
    },
  );

  testWidgets('client details separate overview, history, menus and comments', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final repo = UiRepository()
      ..savedMenus.add(menuFixture())
      ..commentRows.add({
        'body': 'Form cue',
        'shared_with_client': false,
        'created_at': '2026-09-25',
      })
      ..historyRows.add({
        'performed_at': '2026-09-25T10:00:00Z',
        'record_source': 'trainer',
        'sets': [
          {
            'exerciseId': 'bench_press',
            'exerciseName': 'Bench press',
            'recordType': 'weightReps',
            'weight': 25,
            'reps': 8,
            'completed': true,
          },
        ],
      });
    await t.pumpWidget(
      MaterialApp(
        theme: familyTheme(FamilyPalette.trainer),
        home: ClientPage(repository: repo, link: link(recording: true)),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Record session'), findsOneWidget);
    expect(find.text('Create menu'), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
    await t.tap(find.text('History'));
    await t.pumpAndSettle();
    expect(find.textContaining('Trainer record'), findsOneWidget);
    await t.tap(find.text('Menus'));
    await t.pumpAndSettle();
    expect(find.text('Strength A'), findsOneWidget);
    await t.tap(find.text('Comments'));
    await t.pumpAndSettle();
    expect(find.text('Form cue'), findsOneWidget);
    expect(find.text('Trainers only'), findsOneWidget);
    expect(find.text('Add comment'), findsOneWidget);
  });

  testWidgets(
    'tenant management separates staff, clients, assignments and billing',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repo = ManagementRepository()
        ..links.add({...link(), 'id': 'client-id'});
      await t.pumpWidget(
        MaterialApp(
          theme: familyTheme(FamilyPalette.trainer),
          home: TenantManagement(
            repository: repo,
            tenant: const {
              'id': 'tenant-a',
              'name': 'Tenant A',
              'billing_owner_id': 'trainer-id',
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Members'), findsOneWidget);
      await t.tap(find.text('Clients'));
      await t.pumpAndSettle();
      expect(find.text('Client management'), findsOneWidget);
      await t.tap(find.text('Assignments'));
      await t.pumpAndSettle();
      expect(find.text('Trainer assignments'), findsOneWidget);
      await t.ensureVisible(find.text('Billing'));
      await t.tap(find.text('Billing'));
      await t.pumpAndSettle();
      expect(find.text('¥3980 / month'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
