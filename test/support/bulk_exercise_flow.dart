import 'signed_in_auth.dart';
import 'legal_consent_fixture.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Scope scrolling to the picker list, excluding its text field's Scrollable.
Finder exercisePickerScrollable() => find.descendant(
  of: find.descendant(of: find.byType(ExercisePickerSheet), matching: find.byType(ListView)),
  matching: find.byType(Scrollable),
);

Future<void> openExerciseCategory(WidgetTester tester, String category) async {
  final card = find.byKey(Key('exerciseCategory$category'));
  await tester.scrollUntilVisible(card, 180, scrollable: exercisePickerScrollable());
  await tester.tap(card);
  await tester.pumpAndSettle();
}

Future<void> selectPickerExercise(WidgetTester tester, String id) async {
  final exercise = exerciseTemplates.firstWhere((item) => item.exerciseId == id);
  await tester.enterText(find.byKey(const Key('exerciseSearchField')), exercise.name);
  await tester.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final row = find.byKey(Key('selectExercise$id'));
  await tester.scrollUntilVisible(row, 100, scrollable: exercisePickerScrollable());
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: row, matching: find.byType(Text)).first);
  await tester.pumpAndSettle();
}

Future<void> verifyBulkExerciseFlow(
  WidgetTester tester, {
  Future<void> Function(String)? screenshot,
}) async {
  const names = ['ダンベルフライ', 'ベンチプレス', 'クランチ'];
  final menu = SavedWorkoutTemplate(
    name: 'まとめて記録',
    sets: [
      for (var i = 0; i < names.length; i++)
        RecordedSet(
          exerciseName: names[i],
          bodyPart: i == 2 ? '腹' : '胸',
          weight: i == 2 ? 0 : 20 + i * 20,
          reps: 10 + i,
          recordType: i == 2
              ? ExerciseRecordType.bodyweightReps
              : ExerciseRecordType.weightReps,
          completed: true,
        ),
    ],
  );
  SharedPreferences.setMockInitialValues({
    'onboarding_completed': true,
    'legal_consent': acceptedLegalConsentJson,
    'workout_templates': jsonEncode([menu.toJson()]),
  });
  await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('startWorkoutButton')));
  await tester.pumpAndSettle();
  Future<void> openMenu() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('addExerciseButton')),
      300,
      scrollable: find
          .descendant(
            of: find.byType(WorkoutPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exercisePickerMyMenuEntry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pickMenuまとめて記録')));
    await tester.pumpAndSettle();
  }

  await openMenu();
  expect(find.text('3種目選択中'), findsOneWidget);
  expect(find.byKey(const Key('clearSelectedExercises')), findsNothing);
  expect(find.byKey(const Key('selectAllExercises')), findsNothing);
  // Return to the menu list before selecting the group again.
  await tester.tap(find.byKey(const Key('backToExerciseCategories')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('pickMenuまとめて記録')));
  await tester.pumpAndSettle();
  expect(find.text('3種目選択中'), findsOneWidget);
  await screenshot?.call('three_exercises_selected');
  await tester.tap(find.byKey(const Key('addSelectedExercises')));
  await tester.pumpAndSettle();
  final prefs = await SharedPreferences.getInstance();
  List<dynamic> exercises() =>
      (jsonDecode(prefs.getString(activeWorkoutDraftStorageKey)!)
              as Map<String, dynamic>)['exercises']
          as List<dynamic>;
  expect(exercises().map((e) => e['name']).toList(), names);
  expect(exercises().first['sets'], hasLength(1));
  expect(exercises().first['sets'][0]['completed'], false);
  await tester.ensureVisible(find.byKey(const Key('weightField0_1')));
  await tester.enterText(find.byKey(const Key('weightField0_1')), '22.5');
  await tester.pumpAndSettle();
  expect(exercises().first['sets'][0]['weight'], 22.5);
  await screenshot?.call('bulk_added_and_weight_edited');
  await openMenu();
  expect(find.text('追加済み'), findsNWidgets(3));
  await tester.tap(find.byKey(const Key('selectExerciseベンチプレス')));
  await tester.pumpAndSettle();
  expect(find.text('0種目選択中'), findsOneWidget);
  expect(
    tester
        .widget<FilledButton>(find.byKey(const Key('addSelectedExercises')))
        .onPressed,
    isNull,
  );
  await tester.tap(find.byKey(const Key('backToExerciseCategories')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('backToExerciseCategories')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('exerciseCategory胸')));
  await tester.tap(find.byKey(const Key('exerciseCategory胸')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('exerciseSearchField')), 'チェストプレス');
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('selectExercisechest_press')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('addSelectedExercises')));
  await tester.pumpAndSettle();
  expect(exercises().map((e) => e['name']).toList(), [...names, 'チェストプレスマシン']);
  expect(exercises().first['sets'][0]['weight'], 22.5);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
}
