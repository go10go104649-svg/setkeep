import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/sharing/share_photo_frame.dart';

Future<Uint8List> photo(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.red,
  );
  canvas.drawRect(
    Rect.fromLTWH(width / 2, 0, width / 2, height.toDouble()),
    Paint()..color = Colors.blue,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

class FakePhotoPicker extends ImagePickerPlatform {
  FakePhotoPicker(this.bytes);
  final Uint8List bytes;
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile.fromData(bytes, mimeType: 'image/png');
}

void main() {
  test('cover crop clamps both extremes and locks axes without overflow', () {
    expect(
      shiftedCoverAlignment(
        const Size(600, 200),
        const Size(200, 200),
        Alignment.center,
        const Offset(10000, 10000),
      ),
      const Alignment(-1, 0),
    );
    expect(
      shiftedCoverAlignment(
        const Size(600, 200),
        const Size(200, 200),
        Alignment.center,
        const Offset(-10000, -10000),
      ),
      const Alignment(1, 0),
    );
    expect(
      shiftedCoverAlignment(
        const Size(200, 600),
        const Size(200, 200),
        Alignment.center,
        const Offset(10000, 10000),
      ),
      const Alignment(0, -1),
    );
    expect(
      shiftedCoverAlignment(
        const Size(200, 200),
        const Size(200, 200),
        Alignment.center,
        const Offset(10000, 10000),
      ),
      Alignment.center,
    );
  });
  testWidgets(
    'drag crop exports the same pixels, keeps foreground fixed, resets with new photo',
    (t) async {
      final bytes = (await t.runAsync(() => photo(600, 200)))!;
      final key = GlobalKey();
      Widget page(Uint8List data) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: RepaintBoundary(
                key: key,
                child: SharePhotoFrame(
                  bytes: data,
                  foreground: const [
                    Align(alignment: Alignment.topLeft, child: Text('SETKEEP')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpWidget(page(bytes));
      await t.runAsync(
        () => precacheImage(
          MemoryImage(bytes),
          t.element(find.byType(SharePhotoFrame)),
        ),
      );
      await t.pumpAndSettle();
      final logoPosition = t.getTopLeft(find.text('SETKEEP'));
      await t.drag(
        find.byKey(const Key('sharePhotoDragSurface')),
        const Offset(1000, 50),
      );
      await t.pumpAndSettle();
      final image = t.widget<Image>(
        find.byKey(const Key('shareBackgroundPhoto')),
      );
      expect(image.alignment, const Alignment(-1, 0));
      expect(t.getTopLeft(find.text('SETKEEP')), logoPosition);
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final pixels = (await t.runAsync(() async {
        final captured = await boundary.toImage(pixelRatio: 1);
        final data = await captured.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        captured.dispose();
        return data;
      }))!;
      final pixel = (150 * 200 + 180) * 4;
      expect(
        pixels.getUint8(pixel),
        244,
      ); // moved crop contains red, rather than blue or empty padding
      expect(pixels.getUint8(pixel + 2), 54);
      expect(pixels.getUint8(pixel + 3), 255);
      final replacement = (await t.runAsync(() => photo(500, 200)))!;
      await t.pumpWidget(page(replacement));
      await t.pumpAndSettle();
      expect(
        t
            .widget<Image>(find.byKey(const Key('shareBackgroundPhoto')))
            .alignment,
        Alignment.center,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'vertical photo drag owns gesture while scrolling outside still works',
    (t) async {
      final bytes = (await t.runAsync(() => photo(100, 400)))!;
      final scroll = ScrollController();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: scroll,
              children: [
                SizedBox(
                  width: 200,
                  height: 200,
                  child: SharePhotoFrame(bytes: bytes, foreground: const []),
                ),
                const SizedBox(height: 1500, child: Text('outside')),
              ],
            ),
          ),
        ),
      );
      await t.runAsync(
        () => precacheImage(
          MemoryImage(bytes),
          t.element(find.byType(SharePhotoFrame)),
        ),
      );
      await t.pumpAndSettle();
      await t.drag(
        find.byKey(const Key('sharePhotoDragSurface')),
        const Offset(0, -100),
      );
      await t.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(
        (t
                    .widget<Image>(
                      find.byKey(const Key('shareBackgroundPhoto')),
                    )
                    .alignment
                as Alignment)
            .y,
        greaterThan(0),
      );
      await t.dragFrom(const Offset(400, 400), const Offset(0, -200));
      await t.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      await t.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );
  testWidgets('share page saves the positioned preview at export resolution', (
    t,
  ) async {
    final bytes = (await t.runAsync(() => photo(600, 200)))!;
    final previousPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = FakePhotoPicker(bytes);
    Uint8List? saved;
    WorkoutImageService.saveOverride = (data) async {
      saved = data;
    };
    addTearDown(() {
      ImagePickerPlatform.instance = previousPicker;
      WorkoutImageService.saveOverride = null;
    });
    await t.pumpWidget(
      MaterialApp(
        home: WorkoutSharePage(
          workout: WorkoutRecord(
            date: DateTime(2026, 10, 3),
            sets: const [RecordedSet(weight: 20, reps: 8, completed: true)],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.byKey(const Key('chooseSharePhotoButton')),
      200,
    );
    await t.ensureVisible(find.byKey(const Key('chooseSharePhotoButton')));
    await t.tap(find.byKey(const Key('chooseSharePhotoButton')));
    await t.pumpAndSettle();
    await t.runAsync(
      () => precacheImage(
        MemoryImage(bytes),
        t.element(find.byType(SharePhotoFrame)),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('sharePhotoDragSurface')));
    await t.drag(
      find.byKey(const Key('sharePhotoDragSurface')),
      const Offset(100, 0),
    );
    await t.pumpAndSettle();
    expect(
      (t.widget<Image>(find.byKey(const Key('shareBackgroundPhoto'))).alignment
              as Alignment)
          .x,
      lessThan(0),
    );
    expect(find.byKey(const Key('shareBrandLogo')), findsOneWidget);
    expect(find.text('ベンチプレス'), findsOneWidget);
    final boundary = t.renderObject<RenderRepaintBoundary>(
      find
          .ancestor(
            of: find.byType(SharePhotoFrame),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    final expected = (await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
    final position = t
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(position.maxScrollExtent);
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('shareWorkoutImageButton')));
    await t.runAsync(() async {
      await t.tap(find.byKey(const Key('shareWorkoutImageButton')));
      await t.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await t.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved, orderedEquals(expected));
    expect(t.takeException(), isNull);
  });
}
