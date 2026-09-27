import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/main.dart';

WorkoutRecord record(int day) => WorkoutRecord(
  date: DateTime(2026, 9, day),
  gymName: 'Gym',
  note: 'preserve',
  sets: const [
    RecordedSet(
      exerciseName: 'アシストディップス',
      exerciseId: 'assisted_dips',
      bodyPart: '胸',
      weight: 20,
      reps: 8,
      completed: true,
    ),
    RecordedSet(
      exerciseName: 'ベンチプレス',
      exerciseId: 'bench_press',
      weight: 40,
      reps: 10,
      completed: true,
    ),
    RecordedSet(
      exerciseName: 'ベンチプレス',
      exerciseId: 'bench_press',
      weight: 45,
      reps: 8,
      completed: true,
    ),
  ],
);
Future<List<dynamic>> stored() async => jsonDecode(
  (await SharedPreferences.getInstance()).getString('workout_history')!,
) as List;

void main() {
  testWidgets(
    'deletion survives immediate restart and restores exact record once',
    (tester) async {
      final target = record(26), other = record(25);
      SharedPreferences.setMockInitialValues({
        'workout_history': jsonEncode([target.toJson(), other.toJson()]),
      });
      await tester.pumpWidget(const MaterialApp(home: HomeShell()));
      await tester.pumpAndSettle();
      var home = tester.widget<DashboardPage>(find.byType(DashboardPage));
      // Deserialized copy models a record replaced by sync while its detail is open.
      expect(
        await home.onWorkoutDeleted(WorkoutRecord.fromJson(target.toJson())),
        isTrue,
      );
      expect(await stored(), [other.toJson()]);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(const MaterialApp(home: HomeShell()));
      await tester.pumpAndSettle();
      home = tester.widget<DashboardPage>(find.byType(DashboardPage));
      expect(home.history.map((w) => w.toJson()), [other.toJson()]);
      await home.onWorkoutCompleted(target);
      await home.onWorkoutCompleted(target);
      expect(await stored(), [target.toJson(), other.toJson()]);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(const MaterialApp(home: HomeShell()));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DashboardPage>(find.byType(DashboardPage))
            .history
            .map((w) => w.toJson()),
        [target.toJson(), other.toJson()],
      );
    },
  );

  testWidgets('search results remove a deleted record and Undo restores it', (
    tester,
  ) async {
    final target = record(26);
    await tester.pumpWidget(
      MaterialApp(
        home: HistorySearchPage(
          history: [target],
          selectedGym: null,
          onWorkoutCompleted: (_) async {},
          onWorkoutUpdated: (_, _) async {},
          onWorkoutDeleted: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(HistoryCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('記録を削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除'));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryCard), findsNothing);
    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryCard), findsOneWidget);
  });

  for (final exercise in [true, false]) {
    testWidgets(
      'editing ${exercise ? 'exercise' : 'set'} deletion persists before Undo and Undo persists',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final original = record(26);
        WorkoutRecord saved = original;
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutPage(
              initialWorkout: original,
              isEditing: true,
              onSave: (w) async {
                saved = w;
                await (await SharedPreferences.getInstance()).setString(
                  'workout_history',
                  jsonEncode([w.toJson()]),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          exercise
              ? find.byTooltip('種目を削除').first
              : find.byTooltip('セットを削除').first,
        );
        await tester.pumpAndSettle();
        expect(saved.sets, hasLength(2));
        expect((await stored()).single, saved.toJson());
        final snack = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(snack.duration, const Duration(seconds: 2));
        expect(snack.persist, isFalse);
        await tester.tap(find.text('元に戻す'));
        await tester.pumpAndSettle();
        expect(saved.toJson(), original.toJson());
        expect((await stored()).single, original.toJson());
        await tester.tap(
          exercise
              ? find.byTooltip('種目を削除').first
              : find.byTooltip('セットを削除').first,
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(find.text('元に戻す'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        expect((await stored()).single['sets'], hasLength(2));
      },
    );
  }
}
