import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:setkeep/exercise_form_catalog.dart';
import 'package:setkeep/exercise_media.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'exercise_form_expansion_test.dart' as playback;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'category list opens the matching Vital form through detail route',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const selected = String.fromEnvironment(
        'FORM_QA_IDS',
        defaultValue: 'bench_press,incline_dumbbell_press',
      );
      for (final id in selected.split(',')) {
        final form = ExerciseFormCatalog.byId[id]!;
        final media = ExerciseMediaCatalog.forExerciseId(id);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ExercisePickerSheet(
                key: UniqueKey(),
                existingNames: const {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final category = find.byKey(Key('exerciseCategory${form.category}'));
        await tester.ensureVisible(category);
        await tester.pumpAndSettle();
        await tester.tap(category);
        await tester.pumpAndSettle();
        final button = find.byKey(Key('exerciseDetails${form.exerciseId}'));
        await tester.scrollUntilVisible(
          button,
          300,
          scrollable: find.descendant(
            of: find.byKey(ValueKey('exercisePickerList${form.category}false')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pump();
        expect(find.byType(ExerciseMuscleDetailPage), findsOneWidget);
        for (final label in [
          ...form.primaryMuscleLabels,
          ...form.secondaryMuscleLabels,
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        if (media == null) {
          expect(
            find.byKey(const Key('exerciseFormUnavailable')),
            findsOneWidget,
          );
        } else {
          var visible = false;
          for (var attempt = 0; attempt < 25; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 400));
            await tester.pump();
            if (find.byType(VideoPlayer).evaluate().isNotEmpty) {
              visible = true;
              break;
            }
          }
          expect(visible, isTrue, reason: 'Vital form video: $id');
          await playback.capture(
            binding,
            'vital_route_$id',
            record: !Platform.isAndroid,
          );
        }
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(VideoPlayer), findsNothing);
        expect(button, findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
}
