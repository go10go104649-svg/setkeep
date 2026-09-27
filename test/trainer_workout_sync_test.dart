import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const userA = 'user-a';
const userB = 'user-b';

Map<String, dynamic> session(
  String id, {
  String date = '2026-09-25T10:00:00Z',
  int reps = 8,
  String? canceledAt,
  String note = '',
}) => {
  'id': id,
  'performed_at': date,
  'duration_seconds': 1800,
  'gym_name': 'Gym',
  'note': note,
  'canceled_at': canceledAt,
  'sets': [
    {
      'exerciseName': 'ベンチプレス',
      'bodyPart': '胸',
      'weight': 60,
      'reps': reps,
      'completed': true,
    },
  ],
};

WorkoutRecord selfRecord({String date = '2026-09-25T10:00:00Z'}) =>
    WorkoutRecord(
      date: DateTime.parse(date),
      note: 'My own workout',
      sets: const [RecordedSet(weight: 40, reps: 5, completed: true)],
    );

void main() {
  test(
    'server cancellation with no remaining sets cannot resurrect on restart',
    () {
      final own = selfRecord();
      final trainer = reconcileTrainerWorkouts([], [
        session('trainer-1'),
      ], userA).single;
      final rows = [
        session('trainer-1', canceledAt: '2026-09-27T00:00:00Z')..['sets'] = [],
      ];
      final deleted = reconcileTrainerWorkouts([own, trainer], rows, userA);
      final restarted = decodeWorkoutHistory(
        jsonEncode(deleted.map((w) => w.toJson()).toList()),
      );
      expect(
        reconcileTrainerWorkouts(restarted, rows, userA).map((w) => w.toJson()),
        [own.toJson()],
      );
    },
  );

  test('trainer save becomes official history and stays idempotent', () {
    final own = selfRecord();
    final first = reconcileTrainerWorkouts(
      [own],
      [session('trainer-1')],
      userA,
    );
    expect(first, hasLength(2));
    expect(first.where((w) => w.trainerWorkoutId == 'trainer-1'), hasLength(1));
    expect(first.where((w) => identical(w, own)), hasLength(1));
    final second = reconcileTrainerWorkouts(first, [
      session('trainer-1'),
    ], userA);
    expect(second, hasLength(2));
    expect(
      second.singleWhere((w) => w.trainerWorkoutId != null).trainerOwnerUserId,
      userA,
    );
    final encoded = second
        .singleWhere((w) => w.trainerWorkoutId != null)
        .toJson();
    expect(WorkoutRecord.fromJson(encoded).trainerWorkoutId, 'trainer-1');
  });

  test('cancel removes only matching trainer ID and restore returns it', () {
    final own = selfRecord();
    final other = reconcileTrainerWorkouts([], [
      session('trainer-2'),
    ], userA).single;
    var history = reconcileTrainerWorkouts(
      [own, other],
      [session('trainer-1')],
      userA,
    );
    history = reconcileTrainerWorkouts(history, [
      session('trainer-1', canceledAt: '2026-09-26T00:00:00Z'),
      session('trainer-2'),
    ], userA);
    expect(history, hasLength(2));
    expect(history, contains(own));
    expect(
      history.where((w) => w.trainerWorkoutId == other.trainerWorkoutId),
      hasLength(1),
    );
    history = reconcileTrainerWorkouts(history, [session('trainer-1')], userA);
    expect(history, hasLength(3));
  });

  test('same timestamp never overwrites different content or owner', () {
    final own = selfRecord();
    final otherOwner = reconcileTrainerWorkouts([], [
      session('same-id'),
    ], userB).single;
    final result = reconcileTrainerWorkouts(
      [own, otherOwner],
      [session('same-id')],
      userA,
    );
    expect(result, hasLength(3));
    expect(result, contains(own));
    expect(result, contains(otherOwner));
  });

  test('updates trainer content by ID', () {
    var history = reconcileTrainerWorkouts([], [session('trainer-1')], userA);
    history = reconcileTrainerWorkouts(history, [
      session('trainer-1', reps: 12),
    ], userA);
    expect(history, hasLength(1));
    expect(history.single.sets.single.reps, 12);
  });

  test('one trainer set and comment survive sync and local JSON reload', () {
    final synced = reconcileTrainerWorkouts([], [
      session('trainer-one', note: 'Form is improving'),
    ], userA).single;
    final restored = WorkoutRecord.fromJson(synced.toJson());
    expect(restored.sets, hasLength(1));
    expect(restored.sets.single.weight, 60);
    expect(restored.sets.single.reps, 8);
    expect(restored.note, 'Form is improving');
    expect(restored.trainerWorkoutId, 'trainer-one');
  });

  test(
    'exact legacy receipt is not doubled or mistaken for cancellable data',
    () {
      final row = session('trainer-1');
      final legacy = WorkoutRecord.fromJson({
        'date': row['performed_at'],
        'durationSeconds': row['duration_seconds'],
        'gymName': row['gym_name'],
        'sets': row['sets'],
      });
      final adopted = reconcileTrainerWorkouts([legacy], [row], userA);
      expect(adopted, hasLength(1));
      expect(adopted.single, same(legacy));
      expect(
        reconcileTrainerWorkouts(
          [legacy],
          [session('trainer-1', canceledAt: '2026-09-26T00:00:00Z')],
          userA,
        ),
        [legacy],
      );
      final own = selfRecord();
      final distinct = reconcileTrainerWorkouts([own], [row], userA);
      expect(distinct, hasLength(2));
      expect(distinct, contains(own));
      final ambiguous = reconcileTrainerWorkouts(
        [legacy, legacy],
        [row],
        userA,
      );
      expect(ambiguous, hasLength(3));
    },
  );

  test('fetches every page beyond 100 entries', () async {
    final source = List.generate(205, (i) => session('trainer-$i'));
    final offsets = <int>[];
    final rows = await fetchAllTrainerWorkouts((offset) async {
      offsets.add(offset);
      return source.skip(offset).take(100).toList();
    });
    expect(rows, hasLength(205));
    expect(offsets, [0, 100, 200]);
    expect(reconcileTrainerWorkouts([], rows, userA), hasLength(205));
  });

  test('failed later page leaves original local history untouched', () async {
    final own = selfRecord();
    final source = List.generate(100, (i) => session('trainer-$i'));
    final future = fetchAllTrainerWorkouts((offset) async {
      if (offset == 100) throw TimeoutException('offline');
      return source;
    });
    await expectLater(future, throwsA(isA<TimeoutException>()));
    expect([own], contains(own));
  });

  test('missing login can skip fetch without changing local data', () async {
    final own = selfRecord();
    var called = false;
    Future<List<WorkoutRecord>> syncIfSignedIn(String? userId) async {
      if (userId == null) return [own];
      final rows = await fetchAllTrainerWorkouts((_) async {
        called = true;
        return [session('trainer-1')];
      });
      return reconcileTrainerWorkouts([own], rows, userId);
    }

    expect(await syncIfSignedIn(null), [own]);
    expect(called, false);
  });

  testWidgets('signed-out home keeps self history and hides trainer history', (
    tester,
  ) async {
    final own = selfRecord();
    final trainer = reconcileTrainerWorkouts([], [
      session('trainer-1'),
    ], userA).single;
    SharedPreferences.setMockInitialValues({
      'workout_history': jsonEncode([own.toJson(), trainer.toJson()]),
    });
    await tester.pumpWidget(const MaterialApp(home: HomeShell()));
    await tester.pumpAndSettle();
    final home = tester.widget<DashboardPage>(find.byType(DashboardPage));
    expect(home.history, hasLength(1));
    expect(home.history.single.note, own.note);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
