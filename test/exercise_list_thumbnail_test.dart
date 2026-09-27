import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/exercise_list_thumbnail.dart';
import 'package:setkeep/exercise_media.dart';
import 'package:video_player/video_player.dart';

void main() {
  testWidgets('mapped form uses its Vital still image in a square slot', (
    tester,
  ) async {
    final path = ExerciseMediaCatalog.forExerciseId('bench_press')!
        .thumbnailAssetPath;
    expect(path, 'assets/vital_thumbnails/0042.png');
    if (!File(path!).existsSync()) return; // Purchased media is local-only.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ExerciseListThumbnail(assetPath: path)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('exerciseListThumbnail'))),
      const Size.square(56),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, path);
    expect(image.fit, BoxFit.contain);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new Vital mapping uses a still image without video playback', (
    tester,
  ) async {
    final path = ExerciseMediaCatalog.forExerciseId('lat_pulldown')!
        .thumbnailAssetPath!;
    expect(path, 'assets/vital_thumbnails/0037.png');
    if (!File(path).existsSync()) return;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ExerciseListThumbnail(assetPath: path)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      (tester.widget<Image>(find.byType(Image)).image as AssetImage).assetName,
      path,
    );
    expect(find.byType(VideoPlayer), findsNothing);
  });

  testWidgets('form without a still image uses muted SETKEEP mark', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ExerciseListThumbnail())),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('exerciseListThumbnail'))),
      const Size.square(56),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/brand/setkeep_splash_mark.png',
    );
    expect(image.color, const Color(0xFFAFB5B4));
    expect(image.colorBlendMode, BlendMode.srcIn);
    expect(tester.takeException(), isNull);
  });
}
