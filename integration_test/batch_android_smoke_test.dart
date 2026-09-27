import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android exercise picker and 3D routes open', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SetkeepApp());
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();

    expect(find.text('クイックスタート'), findsNothing);
    expect(find.text('最近鍛えた部位'), findsNothing);
    expect(find.text('体重推移'), findsOneWidget);

    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('emptyWorkoutExercises')), findsOneWidget);

    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    expect(find.text('カスタム'), findsNothing);
    await tester.tap(find.byKey(const Key('exerciseCategory胸')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('addCustomExerciseForCategory')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('exerciseDetailsbench_press')));
    await tester.pumpAndSettle();
    expect(find.byType(VideoPlayer), findsOneWidget);
    await binding.takeScreenshot('android_bench_press_vital');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('exerciseDetailschest_press')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exerciseMuscleModel3D')), findsOneWidget);
    await binding.takeScreenshot('android_chest_press_3d');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android saves the default SNS image to photos', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SetkeepApp());
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(HomeShell));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutSharePage(
          workout: WorkoutRecord(
            date: DateTime.now(),
            durationSeconds: 1800,
            sets: const [
              RecordedSet(
                exerciseName: 'インクラインダンベルプレス（長い種目名の表示確認）',
                bodyPart: '胸',
                weight: 22.5,
                reps: 10,
                completed: true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('トレーニング時間'), findsNothing);
    final saveButton = find.byKey(const Key('shareWorkoutImageButton'));
    await tester.dragUntilVisible(
      saveButton,
      find.byType(ListView),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pump();
    for (var i = 0; i < 30 && find.text('画像を保存中…').evaluate().isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    }
    expect(find.text('画像を写真へ保存しました'), findsOneWidget);
    expect(find.text('画像を保存できませんでした'), findsNothing);
    await binding.takeScreenshot('android_sns_image_saved');
    expect(tester.takeException(), isNull);
  });
}
