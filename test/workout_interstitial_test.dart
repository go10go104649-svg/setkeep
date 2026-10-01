import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/ads/ads_config.dart';
import 'package:setkeep/ads/banner_backend.dart';
import 'package:setkeep/ads/setkeep_banner_ad.dart';
import 'package:setkeep/ads/workout_interstitial.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoBanner implements BannerBackend {
  @override
  bool get supported => false;
  @override
  Future<BannerHandle?> load(
    int width,
    String id,
    BannerRequest request,
  ) async => null;
}

class _FakeAd implements InterstitialHandle {
  int shows = 0;
  int disposals = 0;
  Completer<void>? pending;
  @override
  Future<void> show() {
    shows++;
    return pending?.future ?? Future<void>.value();
  }

  @override
  void dispose() => disposals++;
}

class _FakeBackend implements InterstitialBackend {
  _FakeBackend(this.ad);
  final _FakeAd ad;
  int loads = 0;
  bool fail = false;
  bool pending = false;
  Completer<InterstitialHandle?>? loading;
  @override
  bool get supported => true;
  @override
  Future<InterstitialHandle?> load(String unitId) async {
    loads++;
    if (fail) throw StateError('offline');
    if (pending) {
      loading = Completer<InterstitialHandle?>();
      return loading!.future;
    }
    return ad;
  }
}

Future<void> _primeTwoCompletions() async {
  final prefs = await SharedPreferences.getInstance();
  const policy = WorkoutInterstitialPolicy();
  expect(await policy.recordCompletion(prefs), false);
  expect(await policy.recordCompletion(prefs), false);
}

Future<WorkoutInterstitialSession?> _finish(
  AdsEntitlement entitlement,
  _FakeBackend backend, {
  AdsConfig config = const AdsConfig(generalApp: true),
}) => WorkoutInterstitialSession.afterSavedWorkout(
  config: config,
  entitlement: entitlement,
  platform: TargetPlatform.android,
  backend: backend,
);

String _draft() => jsonEncode({
  'date': DateTime(2026, 9, 30, 18).toIso8601String(),
  'gymName': '自宅',
  'exercises': [
    {
      'name': 'ベンチプレス',
      'exerciseId': 'bench_press',
      'bodyPart': '胸',
      'equipment': 'フリーウェイト',
      'sets': [
        {'weight': 50, 'reps': 8, 'completed': true},
      ],
    },
  ],
});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WorkoutUiPreference.completionCheckEnabled = true;
    WorkoutUiPreference.workoutTimerEnabled = false;
    RestTimerPreference.enabled = false;
  });

  testWidgets('test IDs and TRAINER/production fail closed', (tester) async {
    const config = AdsConfig(generalApp: true);
    expect(
      config.interstitialId(TargetPlatform.android),
      'ca-app-pub-3940256099942544/1033173712',
    );
    expect(
      config.interstitialId(TargetPlatform.iOS),
      'ca-app-pub-3940256099942544/4411468910',
    );
    expect(config.interstitialId(TargetPlatform.macOS), isNull);
    expect(const AdsConfig().interstitialId(TargetPlatform.android), isNull);
    expect(
      const AdsConfig(
        generalApp: true,
        mode: 'production',
      ).interstitialId(TargetPlatform.android),
      isNull,
    );
    final entitlement = AdsEntitlement();
    final backend = _FakeBackend(_FakeAd());
    expect(
      await _finish(entitlement, backend, config: const AdsConfig()),
      isNull,
    );
    expect(backend.loads, 0);
    entitlement.dispose();
  });

  testWidgets(
    'first completion suppressed; third eligible across prefs reads',
    (tester) async {
      final entitlement = AdsEntitlement();
      final backend = _FakeBackend(_FakeAd());
      expect(await _finish(entitlement, backend), isNull);
      expect(await _finish(entitlement, backend), isNull);
      final session = await _finish(entitlement, backend);
      await tester.pump();
      expect(session, isNotNull);
      expect(backend.loads, 1);
      await session!.tryShow();
      expect(backend.ad.shows, 1);
      session.dispose();
      final fourth = await _finish(entitlement, backend);
      expect(fourth, isNull);
      entitlement.dispose();
    },
  );

  testWidgets('adFree skips load; unloaded and failed load skip immediately', (
    tester,
  ) async {
    await _primeTwoCompletions();
    final entitlement = AdsEntitlement(adFree: true);
    final backend = _FakeBackend(_FakeAd());
    expect(await _finish(entitlement, backend), isNull);
    expect(backend.loads, 0);
    entitlement.adFree = false;
    backend.pending = true;
    final session = await _finish(entitlement, backend);
    await session!.tryShow();
    expect(session.attempted, true);
    expect(backend.ad.shows, 0);
    backend.loading!.complete(backend.ad);
    await tester.pump();
    expect(backend.ad.disposals, greaterThan(0));
    session.dispose();
    entitlement.dispose();
  });

  testWidgets('load failure, entitlement change and background never block', (
    tester,
  ) async {
    await _primeTwoCompletions();
    final entitlement = AdsEntitlement();
    final backend = _FakeBackend(_FakeAd())..fail = true;
    final failed = await _finish(entitlement, backend);
    await tester.pump();
    await failed!.tryShow();
    expect(backend.ad.shows, 0);
    failed.dispose();

    SharedPreferences.setMockInitialValues({'ads_completed_workouts_v1': 2});
    backend.fail = false;
    final adFree = await _finish(entitlement, backend);
    await tester.pump();
    entitlement.adFree = true;
    await adFree!.tryShow();
    expect(backend.ad.shows, 0);
    adFree.dispose();
    entitlement.adFree = false;

    SharedPreferences.setMockInitialValues({'ads_completed_workouts_v1': 2});
    final background = await _finish(entitlement, backend);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await background!.tryShow();
    expect(backend.ad.shows, 0);
    background.dispose();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    entitlement.dispose();
  });

  testWidgets('double show, lifecycle, entitlement and dispose are safe', (
    tester,
  ) async {
    await _primeTwoCompletions();
    final entitlement = AdsEntitlement();
    final backend = _FakeBackend(_FakeAd()..pending = Completer<void>());
    final session = await _finish(entitlement, backend);
    await tester.pump();
    final first = session!.tryShow();
    await session.tryShow();
    expect(backend.ad.shows, 1);
    backend.ad.pending!.complete();
    await first;
    session.dispose();
    await session.tryShow();
    expect(backend.ad.shows, 1);
    entitlement.dispose();
  });

  testWidgets('no-save exit attempts ad after saved workout, once', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      activeWorkoutDraftStorageKey: _draft(),
      'ads_completed_workouts_v1': 2,
    });
    final entitlement = AdsEntitlement();
    final backend = _FakeBackend(_FakeAd());
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AdsScope(
          config: const AdsConfig(generalApp: true),
          entitlement: entitlement,
          backend: _NoBanner(),
          interstitialBackend: backend,
          child: child!,
        ),
        home: const HomeShell(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('activeWorkoutDraftCard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();
    expect(find.text('トレーニング完了'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(
      decodeWorkoutHistory(prefs.getString('workout_history')),
      hasLength(1),
    );
    expect(prefs.getString(activeWorkoutDraftStorageKey), isNull);
    await tester.tap(find.byKey(const Key('completeWithoutSharingButton')));
    await tester.pumpAndSettle();
    expect(backend.ad.shows, 1);
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.byType(WorkoutPage), findsNothing);
    entitlement.dispose();
  });

  testWidgets('saved image shows then returns home; Back does not show twice', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      activeWorkoutDraftStorageKey: _draft(),
      'ads_completed_workouts_v1': 2,
    });
    int saves = 0;
    WorkoutImageService.saveOverride = (_) async {
      saves++;
    };
    addTearDown(() => WorkoutImageService.saveOverride = null);
    final entitlement = AdsEntitlement();
    final backend = _FakeBackend(_FakeAd());
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AdsScope(
          config: const AdsConfig(generalApp: true),
          entitlement: entitlement,
          backend: _NoBanner(),
          interstitialBackend: backend,
          child: child!,
        ),
        home: const HomeShell(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('activeWorkoutDraftCard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('completeAndPreviewShareButton')));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutSharePage), findsOneWidget);
    await tester.tap(find.byKey(const Key('shareWorkoutImageButton')));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(backend.ad.shows, 1);
    expect(find.byType(WorkoutSharePage), findsNothing);
    expect(find.byType(DashboardPage), findsOneWidget);
    entitlement.dispose();
  });
}
