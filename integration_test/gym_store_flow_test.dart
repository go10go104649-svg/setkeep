import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/config/supabase_config.dart';
import 'package:setkeep/gym/gym_pages.dart';
import 'package:setkeep/gym/gym_repository.dart';
import 'package:setkeep/gym/place_equipment_pages.dart';
import 'package:setkeep/gym/training_place_preference.dart';
import 'package:setkeep/services/android_workout_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final (searchTerm, expectedChainId) in [
    ('野田柳沢', 'fit-place24'),
    ('上石神井', 'fastgym24'),
    ('東松山店', 'fit24'),
    ('松戸駅前店', 'anytime-fitness'),
  ]) {
    testWidgets(
      'live $expectedChainId search equipment exercise and workout draft',
      (t) async {
        SharedPreferences.setMockInitialValues({});
        await SupabaseConfig.initialize();
        expect(SupabaseConfig.initialized, isTrue);
        await AndroidWorkoutDraft.clear();
        WorkoutUiPreference.workoutTimerEnabled = false;
        WorkoutUiPreference.workoutDurationEnabled = false;
        RestTimerPreference.enabled = false;
        final repo = SupabaseGymRepository();
        final stores = await repo.search(searchTerm);
        expect(stores, isNotEmpty);
        final store = stores.firstWhere(
          (store) => store.chainId == expectedChainId,
        );
        final equipment = await repo.equipment(store.id);
        final target = equipment.firstWhere((e) => e.exerciseIds.isNotEmpty);
        final exerciseId = target.exerciseIds.first;
        Future<void> settleUntil(Finder finder) async {
          for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
            await t.pump(const Duration(milliseconds: 100));
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(finder, findsWidgets);
          await t.pumpAndSettle();
        }

        await t.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: const WorkoutPage(),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('workoutGymButton')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('searchRegisteredGymStores')));
        await t.pump();
        await t.enterText(
          find.byKey(const Key('gymStoreSearchField')),
          searchTerm,
        );
        await settleUntil(find.byKey(Key('selectGymStore${store.id}')));
        await t.tap(find.byKey(Key('selectGymStore${store.id}')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('confirmGymStoreSelection')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('workoutGymEquipmentButton')));
        await t.pump();
        await settleUntil(
          find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith('gymEquipment'),
          ),
        );
        await t.scrollUntilVisible(
          find.byKey(Key('gymEquipment${target.id}')),
          300,
          scrollable: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        );
        await t.ensureVisible(find.byKey(Key('gymEquipment${target.id}')));
        await t.tap(find.byKey(Key('gymEquipment${target.id}')));
        await t.pumpAndSettle();
        final add = find.byKey(Key('addGymExercise$exerciseId'));
        await t.ensureVisible(add);
        await t.tap(add);
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('addSelectedGymExercises')));
        await t.pumpAndSettle();
        await t.pageBack();
        await t.pumpAndSettle();
        await t.pageBack();
        await t.pumpAndSettle();
        expect(find.byKey(const Key('exerciseInputHeader0')), findsOneWidget);
        final draft = jsonDecode((await AndroidWorkoutDraft.read())!);
        expect(draft['gymStoreId'], store.id);
        expect((draft['exercises'] as List).single['exerciseId'], exerciseId);
        if (Platform.isAndroid) {
          await binding.convertFlutterSurfaceToImage();
          await t.pumpAndSettle();
        }
        await binding.takeScreenshot('gym_store_exercise_added');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      },
    );
  }
  testWidgets('live FASTGYM24 and Anytime stores register and set default', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await SupabaseConfig.initialize();
    final repo = SupabaseGymRepository();
    final store = (await repo.search('上石神井'))
        .firstWhere((store) => store.chainId == 'fastgym24');
    await t.pumpWidget(const MaterialApp(home: RegisteredGymsPage()));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('registerGymButton')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('gymStoreSearchField')), '上石神井');
    for (
      var i = 0;
      i < 100 &&
          find.byKey(Key('selectGymStore${store.id}')).evaluate().isEmpty;
      i++
    ) {
      await t.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await t.tap(find.byKey(Key('selectGymStore${store.id}')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirmGymStoreSelection')));
    await t.pumpAndSettle();
    expect(
      (await repo.registered()).any((saved) => saved.id == store.id),
      isTrue,
    );
    await t.tap(find.byKey(Key('removeRegisteredGym${store.id}')));
    await t.pumpAndSettle();
    expect(
      (await repo.registered()).any((saved) => saved.id == store.id),
      isFalse,
    );
    final anytime = (await repo.search('松戸駅前店'))
        .firstWhere((item) => item.chainId == 'anytime-fitness');
    await t.tap(find.byKey(const Key('registerGymButton')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('gymStoreSearchField')), '松戸駅前店');
    for (
      var i = 0;
      i < 100 &&
          find.byKey(Key('selectGymStore${anytime.id}')).evaluate().isEmpty;
      i++
    ) {
      await t.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await t.tap(find.byKey(Key('selectGymStore${anytime.id}')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirmGymStoreSelection')));
    await t.pumpAndSettle();
    expect((await repo.registered()).any((s) => s.id == anytime.id), isTrue);
    await t.tap(find.byKey(Key('defaultTrainingPlace${anytime.id}')));
    await t.pumpAndSettle();
    expect((await TrainingPlacePreference.forNewWorkout()).storeId, anytime.id);
    await t.tap(find.byKey(Key('removeRegisteredGym${anytime.id}')));
    await t.pumpAndSettle();
    expect((await TrainingPlacePreference.load()).isHome, isTrue);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'private equipment uses live master and rules without shared writes',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      await SupabaseConfig.initialize();
      await AndroidWorkoutDraft.clear();
      await CustomGymPreference.load();
      await CustomGymPreference.add('QA本人専用場所');
      final id = CustomGymPreference.idFor('QA本人専用場所')!;
      final repo = SupabaseGymRepository();
      final rack = (await repo.searchEquipment('BULL パワーラック'))
          .firstWhere((e) => e.id == 'kanekin:bull-power-rack');
      final bench = (await repo.searchEquipment('BULL アジャスタブルベンチ'))
          .firstWhere((e) => e.id == 'kanekin:bull-adjustable-bench');
      await repo.savePrivateEquipment(
        id,
        PrivatePlaceEquipment(
          id: 'rack',
          equipmentId: rack.id,
          name: rack.name,
        ),
      );
      expect(
        (await repo.privateEvidence(id))
            .any((e) => e.exerciseId == 'incline_barbell_press'),
        isFalse,
      );
      await repo.savePrivateEquipment(
        id,
        PrivatePlaceEquipment(
          id: 'bench',
          equipmentId: bench.id,
          name: bench.name,
        ),
      );
      expect(
        (await repo.privateEvidence(id))
            .any((e) => e.exerciseId == 'incline_barbell_press'),
        isTrue,
      );
      await t.pumpWidget(
        MaterialApp(
          home: PrivatePlaceEquipmentPage(placeId: id, name: 'QA本人専用場所'),
        ),
      );
      for (
        var i = 0;
        i < 80 &&
            find.byKey(const Key('privateEquipmentrack')).evaluate().isEmpty;
        i++
      ) {
        await t.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await t.pumpAndSettle();
      expect(find.byKey(const Key('privateEquipmentrack')), findsOneWidget);
      expect(find.byKey(const Key('reportGymEquipment')), findsNothing);
      await TrainingPlacePreference.save(
        const TrainingPlace.manual('QA本人専用場所'),
      );
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        const MaterialApp(home: WorkoutPage(useDefaultPlace: true)),
      );
      await t.pumpAndSettle();
      expect(find.text('この場所の設備から種目を追加'), findsOneWidget);
      if (Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        await t.pumpAndSettle();
      }
      await binding.takeScreenshot('private_place_workout');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
