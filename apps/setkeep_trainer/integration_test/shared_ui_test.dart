// Run only on disposable QA simulators/emulators. No Auth or production DB is used.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/main.dart' show ExerciseInputCard, ExercisePickerSheet;
import 'package:setkeep_trainer/menu_editor.dart';
import 'package:setkeep_trainer/main.dart' show TrainerApp, ClientPage;
import 'package:setkeep_trainer/trainer_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/trainer_app_test.dart'
    show FakeAuth, FakeRepository, link, menuFixture;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native shared body, per-set editor and category assets', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(
      MaterialApp(
        theme: familyTheme(FamilyPalette.trainer),
        home: HeatmapPage(
          workouts: [
            {
              'performed_at': DateTime.now().toIso8601String(),
              'duration_seconds': 0,
              'sets': [
                {
                  'exerciseId': 'bench_press',
                  'exerciseName': 'ベンチプレス',
                  'bodyPart': '胸',
                  'weight': 20.0,
                  'reps': 10,
                  'completed': true,
                },
              ],
            },
          ],
        ),
      ),
    );
    await t.pumpAndSettle();
    await Future<void>.delayed(const Duration(seconds: 5));
    await t.pump();
    expect(find.byKey(const Key('muscleModel3D')), findsOneWidget);
    debugPrint('TENANT_QA_BODY_READY');
    await Future<void>.delayed(const Duration(seconds: 15));
    await t.pumpWidget(
      MaterialApp(
        theme: familyTheme(FamilyPalette.trainer),
        home: MenuEditor(
          repository: FakeRepository(),
          clients: [link()],
          existing: menuFixture(),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(ExerciseInputCard), findsOneWidget);
    await t.scrollUntilVisible(
      find.byKey(const Key('addSetButton')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      t.element(find.byKey(const Key('addSetButton'))),
      alignment: 0.4,
    );
    await t.pumpAndSettle();
    if (t.getCenter(find.byKey(const Key('addSetButton'))).dy > 650) {
      await t.drag(find.byType(ListView).first, const Offset(0, -220));
      await t.pumpAndSettle();
    }
    await t.tap(find.byKey(const Key('addSetButton')));
    await t.pumpAndSettle();
    expect(
      t.widget<ExerciseInputCard>(find.byType(ExerciseInputCard)).exercise.sets,
      hasLength(3),
    );
    expect(find.byKey(const Key('toggleAllSets0')), findsNothing);
    debugPrint('TENANT_QA_EDITOR_READY');
    await Future<void>.delayed(const Duration(seconds: 15));
    await t.scrollUntilVisible(
      find.text('Add exercise'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      t.element(find.text('Add exercise')),
      alignment: 0.4,
    );
    await t.pumpAndSettle();
    if (t.getCenter(find.text('Add exercise')).dy > 650) {
      await t.drag(find.byType(ListView).first, const Offset(0, -220));
      await t.pumpAndSettle();
    }
    await t.tap(find.text('Add exercise'));
    await t.pumpAndSettle();
    expect(find.byType(ExercisePickerSheet), findsOneWidget);
    debugPrint('TENANT_QA_PICKER_READY');
    await Future<void>.delayed(const Duration(seconds: 15));
    expect(t.takeException(), isNull);
  });

  testWidgets('native trainer navigation reaches client and session editor', (
    t,
  ) async {
    Finder label(String en, String ja) =>
        find.text(en).evaluate().isNotEmpty ? find.text(en) : find.text(ja);
    final auth = FakeAuth();
    addTearDown(auth.events.close);
    final repo = FakeRepository()
      ..links.add({
        ...link(recording: true),
        'linked_user_id': 'client-user',
        'share_workouts': true,
      });
    await t.pumpWidget(TrainerApp(auth: auth, repository: repo));
    await t.pumpAndSettle();
    expect(label('Quick actions', 'クイックアクション'), findsOneWidget);
    await t.tap(label('Clients', '顧客'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('clientSearchField')), findsOneWidget);
    await t.tap(find.widgetWithText(ListTile, 'Client'));
    await t.pumpAndSettle();
    expect(find.byType(ClientPage), findsOneWidget);
    await t.tap(label('Comments', 'コメント'));
    await t.pumpAndSettle();
    expect(label('Add comment', 'コメントを追加'), findsOneWidget);
    await t.tap(label('Overview', '概要'));
    await t.pumpAndSettle();
    await t.tap(label('Record session', 'セッションを記録'));
    await t.pumpAndSettle();
    expect(find.byType(MenuEditor), findsOneWidget);
    expect(label('Save', '保存'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
