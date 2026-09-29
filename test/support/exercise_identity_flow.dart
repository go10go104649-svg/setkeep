import 'signed_in_auth.dart';
import 'legal_consent_fixture.dart';
import 'bulk_exercise_flow.dart' show exercisePickerScrollable;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> verifyIdentityFlow(
  WidgetTester t, {
  Future<void> Function(String)? screenshot,
}) async {
  SharedPreferences.setMockInitialValues({'onboarding_completed': true, 'legal_consent': acceptedLegalConsentJson});
  CustomExercisePreference.exercises = [];
  await t.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
  await t.pumpAndSettle();
  Future<void> tap(Key key) async {
    if (find.byKey(key).evaluate().isEmpty) {
      await t.scrollUntilVisible(
        find.byKey(key),
        250,
        scrollable: exercisePickerScrollable(),
      );
    }
    await t.ensureVisible(find.byKey(key));
    await t.pumpAndSettle();
    await t.tap(find.byKey(key));
    await t.pumpAndSettle();
  }

  await tap(const Key('startWorkoutButton'));
  await tap(const Key('addExerciseButton'));
  await tap(const Key('exerciseCategory肩'));
  await t.enterText(find.byKey(const Key('exerciseSearchField')), 'ショルダープレス');
  await t.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  await tap(const Key('selectExerciseshoulder_press'));
  await tap(const Key('selectExerciseplate_loaded_shoulder_press'));
  expect(find.text('2種目選択中'), findsOneWidget);
  await screenshot?.call('same_name_picker');
  await tap(const Key('addSelectedExercises'));
  final prefs = await SharedPreferences.getInstance();
  final draft = prefs.getString(activeWorkoutDraftStorageKey)!;
  final data = jsonDecode(draft) as Map;
  expect((data['exercises'] as List).map((e) => e['exerciseId']).toSet(), {
    'shoulder_press',
    'plate_loaded_shoulder_press',
  });
  expect(WorkoutDraftSummary.tryParse(draft)!.exerciseNames, hasLength(2));

  // Re-create the actual app to exercise the existing draft read path.
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpAndSettle();
  await t.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
  await t.pumpAndSettle();
  await tap(const Key('activeWorkoutDraftCard'));
  final cards = t
      .widgetList<ExerciseInputCard>(find.byType(ExerciseInputCard))
      .toList();
  expect(cards.map((c) => c.exercise.exerciseId).toSet(), {
    'shoulder_press',
    'plate_loaded_shoulder_press',
  });
  await tap(const Key('toggleSet0_1'));
  await tap(const Key('toggleSet1_1'));
  await screenshot?.call('same_name_workout');
  await tap(const Key('completeWorkoutButton'));
  final complete = t.widgetList<WorkoutSharePage>(
    find.byType(WorkoutSharePage),
  );
  expect(complete, isEmpty);
  await tap(const Key('completeWithoutSharingButton'));
  final history = decodeWorkoutHistory(prefs.getString('workout_history'));
  expect(history, hasLength(1));
  expect(history.single.exerciseGroups, hasLength(2));
  final backup = SetkeepBackup(workouts: history);
  expect(
    SetkeepBackup.fromJson(jsonDecode(jsonEncode(backup.toJson())))
        .workouts
        .single
        .exerciseGroups,
    hasLength(2),
  );

  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpAndSettle();
  await t.pumpWidget(
    MaterialApp(
      home: WorkoutPage(initialWorkout: history.single, isEditing: true),
    ),
  );
  await t.pumpAndSettle();
  expect(
    t
        .widgetList<ExerciseInputCard>(find.byType(ExerciseInputCard))
        .map((c) => c.exercise.exerciseId)
        .toSet(),
    {'shoulder_press', 'plate_loaded_shoulder_press'},
  );
  await screenshot?.call('same_name_edit');
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpAndSettle();
  await t.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
  await t.pumpAndSettle();
  await tap(const Key('startWorkoutButton'));
  await tap(const Key('addExerciseButton'));
  await tap(const Key('exerciseCategoryHYROX'));
  await screenshot?.call('hyrox_category');
  await tap(const Key('selectExercisehyrox_sled_push'));
  await tap(const Key('addSelectedExercises'));
  final distance = find.descendant(
    of: find.byKey(const Key('distanceField0_')),
    matching: find.byType(TextFormField),
  );
  await t.ensureVisible(distance);
  await t.enterText(distance, '50');
  final weight = find.descendant(
    of: find.byKey(const Key('loadedWeightField0_')),
    matching: find.byType(TextFormField),
  );
  await t.ensureVisible(weight);
  await t.enterText(weight, '75');
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  await screenshot?.call('hyrox_loaded_distance');
  await tap(const Key('completeWorkoutButton'));
  await tap(const Key('completeWithoutSharingButton'));
  final loaded = decodeWorkoutHistory(prefs.getString('workout_history'))
      .expand((w) => w.sets)
      .singleWhere((s) => s.exerciseId == 'hyrox_sled_push');
  expect(loaded.weight, 75);
  expect(loaded.distanceKm, .05);
  expect(loaded.distanceUnit, 'm');
  expect(loaded.recordType, ExerciseRecordType.loadedDistance);
  expect(loaded.displaySummary, contains('50 m'));
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}
