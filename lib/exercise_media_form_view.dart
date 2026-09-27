import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'exercise_media.dart';

final RouteObserver<PageRoute<dynamic>> exerciseMediaRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

/// Read-only form video player with a non-3D fallback for missing media.
class ExerciseMediaFormView extends StatefulWidget {
  const ExerciseMediaFormView({
    super.key,
    required this.media,
    required this.fallback,
    this.assetAvailable,
  });

  final ExerciseMedia media;
  final Widget fallback;
  final Future<bool> Function(ExerciseMedia)? assetAvailable;

  @override
  State<ExerciseMediaFormView> createState() => _ExerciseMediaFormViewState();
}

class _ExerciseMediaFormViewState extends State<ExerciseMediaFormView>
    with WidgetsBindingObserver, RouteAware {
  VideoPlayerController? _controller;
  PageRoute<dynamic>? _route;
  bool _loading = true;
  bool _failed = false;
  bool _appForeground = true;
  bool _routeVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appForeground =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _open();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _route) {
      exerciseMediaRouteObserver.unsubscribe(this);
      _route = route;
      _routeVisible = route.isCurrent;
      exerciseMediaRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    unawaited(_syncPlayback());
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    unawaited(_syncPlayback());
  }

  @override
  void didUpdateWidget(covariant ExerciseMediaFormView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media != widget.media) {
      _controller?.removeListener(_onPlayerChange);
      _controller?.dispose();
      _controller = null;
      _loading = true;
      _failed = false;
      _open();
    }
  }

  Future<void> _open() async {
    final media = widget.media;
    try {
      final available =
          await (widget.assetAvailable?.call(media) ??
              ExerciseMediaCatalog.isAvailable(media));
      if (!mounted || widget.media != media) return;
      if (!available) {
        setState(() {
          _loading = false;
          _failed = true;
        });
        return;
      }
      final controller = media.videoUrl == null
          ? VideoPlayerController.asset(
              media.assetPath,
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            )
          : VideoPlayerController.networkUrl(
              media.videoUrl!,
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            );
      _controller = controller;
      await controller.initialize();
      await controller.setVolume(0);
      await controller.setLooping(true);
      if (!mounted || widget.media != media) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onPlayerChange);
      setState(() => _loading = false);
      await _syncPlayback();
    } catch (_) {
      if (widget.media == media) {
        final controller = _controller;
        _controller = null;
        controller?.removeListener(_onPlayerChange);
        if (controller != null) await controller.dispose();
        if (mounted) {
          setState(() {
            _loading = false;
            _failed = true;
          });
        }
      }
    }
  }

  void _onPlayerChange() {
    if (_controller?.value.hasError == true && mounted && !_failed) {
      setState(() => _failed = true);
    }
  }

  Future<void> _syncPlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _failed) {
      return;
    }
    try {
      if (_appForeground && _routeVisible) {
        await controller.play();
      } else {
        await controller.pause();
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appForeground = state == AppLifecycleState.resumed;
    unawaited(_syncPlayback());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    exerciseMediaRouteObserver.unsubscribe(this);
    _controller?.removeListener(_onPlayerChange);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback;
    final controller = _controller;
    return ClipRRect(
      key: const Key('exerciseVitalVideoCard'),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: controller?.value.isInitialized == true
            ? controller!.value.aspectRatio
            : 1,
        child: _loading || controller?.value.isInitialized != true
            ? const Center(child: CircularProgressIndicator())
            : ClipRect(
                // Some hardware decoders expose colored padding at texture
                // edges. Keep the outer ratio/size, sampling just inside the
                // decoded frame on every edge (about 1% per side).
                child: Transform.scale(
                  scale: 1.02,
                  child: VideoPlayer(controller!),
                ),
              ),
      ),
    );
  }
}
