import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// Move only the cover crop. A zero-overflow axis cannot move or reveal a gap.
Alignment shiftedCoverAlignment(
  Size source,
  Size frame,
  Alignment current,
  Offset delta,
) {
  if (source.isEmpty || frame.isEmpty) return Alignment.center;
  final scale = math.max(
    frame.width / source.width,
    frame.height / source.height,
  );
  final overflowX = math.max(0.0, source.width * scale - frame.width);
  final overflowY = math.max(0.0, source.height * scale - frame.height);
  return Alignment(
    overflowX < 0.001
        ? 0
        : (current.x - 2 * delta.dx / overflowX).clamp(-1.0, 1.0),
    overflowY < 0.001
        ? 0
        : (current.y - 2 * delta.dy / overflowY).clamp(-1.0, 1.0),
  );
}

/// The same positioned photo is painted inside the export RepaintBoundary.
/// Foreground branding and workout text remain fixed while the crop moves.
class SharePhotoFrame extends StatefulWidget {
  const SharePhotoFrame({
    super.key,
    required this.bytes,
    required this.foreground,
  });
  final Uint8List? bytes;
  final List<Widget> foreground;
  @override
  State<SharePhotoFrame> createState() => _SharePhotoFrameState();
}

class _SharePhotoFrameState extends State<SharePhotoFrame> {
  Alignment alignment = Alignment.center;
  Size? source;
  ImageStream? stream;
  ImageStreamListener? listener;
  int? activePointer;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (stream == null && widget.bytes != null) resolve();
  }

  @override
  void didUpdateWidget(SharePhotoFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes) {
      alignment = Alignment.center;
      source = null;
      resolve();
    }
  }

  void detach() {
    if (listener != null) stream?.removeListener(listener!);
    listener = null;
    stream = null;
  }

  void resolve() {
    detach();
    final bytes = widget.bytes;
    if (bytes == null) return;
    stream = MemoryImage(bytes).resolve(createLocalImageConfiguration(context));
    listener = ImageStreamListener(
      (info, synchronous) {
        final size = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        info.dispose();
        if (!mounted) return;
        if (synchronous) {
          source = size;
        } else {
          setState(() => source = size);
        }
      },
      onError: (Object _, StackTrace? _) {
        // Image widget reports decoding failure; disable dragging.
        source = null;
      },
    );
    stream!.addListener(listener!);
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final draggable = widget.bytes != null && source != null;
      return RawGestureDetector(
        key: const Key('sharePhotoDragSurface'),
        behavior: HitTestBehavior.opaque,
        gestures: draggable
            ? {
                EagerGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      EagerGestureRecognizer
                    >(EagerGestureRecognizer.new, (instance) {}),
              }
            : const {},
        child: Listener(
          onPointerDown: draggable
              ? (event) => activePointer ??= event.pointer
              : null,
          onPointerUp: (event) {
            if (activePointer == event.pointer) activePointer = null;
          },
          onPointerCancel: (event) {
            if (activePointer == event.pointer) activePointer = null;
          },
          onPointerMove: draggable
              ? (event) {
                  if (activePointer != event.pointer) return;
                  setState(
                    () => alignment = shiftedCoverAlignment(
                      source!,
                      constraints.biggest,
                      alignment,
                      event.localDelta,
                    ),
                  );
                }
              : null,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (widget.bytes == null)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF26313A), Color(0xFF0D1216)],
                      ),
                    ),
                  )
                else
                  Image.memory(
                    widget.bytes!,
                    key: const Key('shareBackgroundPhoto'),
                    fit: BoxFit.cover,
                    alignment: alignment,
                    gaplessPlayback: true,
                  ),
                ...widget.foreground,
              ],
            ),
          ),
        ),
      );
    },
  );
}
