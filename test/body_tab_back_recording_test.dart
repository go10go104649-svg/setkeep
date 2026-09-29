import 'support/signed_in_auth.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/body_tab_colors.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/muscle_targets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/legal_consent_fixture.dart';

void main() {
  test('catalog categories survive history storage and body aggregation', () {
    final now = DateTime(2026, 9, 21, 12);
    final expected = <String, int>{};
    final sets = exerciseTemplates.map((exercise) {
      expect(
        exercise.bodyPart,
        isIn(['胸', '背中', '脚', '肩', '腕', '腹', '有酸素', 'HYROX']),
        reason: exercise.exerciseId,
      );
      expected.update(exercise.bodyPart, (n) => n + 1, ifAbsent: () => 1);
      return RecordedSet(
        exerciseId: exercise.exerciseId,
        exerciseName: exercise.name,
        bodyPart: exercise.bodyPart,
        recordType: exercise.recordType,
        weight: 20,
        reps: 10,
        completed: true,
      );
    }).toList();
    final history = decodeWorkoutHistory(
      jsonEncode([WorkoutRecord(date: now, sets: sets).toJson()]),
    );
    final counts = bodyPartSetCounts(history, MuscleMapPeriod.week, now: now);
    expect(counts, expected);
    expect(counts['背中'], greaterThan(0));
    final scores = bodyTabRelativeIntensities(counts);
    expect(scores[MuscleRegion.latissimusDorsi], greaterThan(0));
    expect(scores[MuscleRegion.trapezius], greaterThan(0));
    final strengthOnly = Map<String, int>.of(counts)
      ..remove('有酸素')
      ..remove('HYROX');
    expect(scores, bodyTabRelativeIntensities(strengthOnly));
  });

  testWidgets(
    'back picker saves history and lights the body map after reload',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'onboarding_completed': true,
        'legal_consent': acceptedLegalConsentJson,
      });
      CustomExercisePreference.exercises = [];
      await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth()));
      await tester.pumpAndSettle();
      Future<void> tap(String key) async {
        final target = find.byKey(Key(key));
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await tap('startWorkoutButton');
      await tap('addExerciseButton');
      await tap('exerciseCategory背中');
      await tester.enterText(
        find.byKey(const Key('exerciseSearchField')),
        'ラットプルダウン',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tap('selectExerciselat_pulldown');
      await tap('addSelectedExercises');
      await tap('toggleSet0_1');
      await tap('completeWorkoutButton');
      await tap('completeWithoutSharingButton');

      final preferences = await SharedPreferences.getInstance();
      final history = decodeWorkoutHistory(
        preferences.getString('workout_history'),
      );
      expect(history, hasLength(1));
      expect(history.single.sets.single.bodyPart, '背中');
      expect(history.single.sets.single.completed, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BodyMapPage(history: history)),
        ),
      );
      await tester.pumpAndSettle();
      final model = tester.widget<MuscleMannequinView>(
        find.byType(MuscleMannequinView),
      );
      expect(model.scores[MuscleRegion.latissimusDorsi], 1);
      expect(model.scores[MuscleRegion.trapezius], 1);
      await tester.scrollUntilVisible(
        find.byKey(const Key('muscleCount背中')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('muscleCount背中'))).data,
        '1セット',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
