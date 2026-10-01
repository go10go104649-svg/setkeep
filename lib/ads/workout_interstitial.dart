import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ads_config.dart';

/// Frequency belongs to the ad policy, never to a workout screen or history.
class WorkoutInterstitialPolicy {
  const WorkoutInterstitialPolicy({this.everyCompletions = 3});
  final int everyCompletions;
  static const _countKey = 'ads_completed_workouts_v1';

  Future<bool> recordCompletion(SharedPreferences prefs) async {
    final count = prefs.getInt(_countKey) ?? 0;
    final next = count + 1;
    if (!await prefs.setInt(_countKey, next)) return false;
    return next > 1 && next % everyCompletions == 0;
  }
}

abstract class InterstitialHandle {
  Future<void> show();
  void dispose();
}

abstract class InterstitialBackend {
  bool get supported;
  Future<InterstitialHandle?> load(String unitId);
}

class GoogleInterstitialBackend implements InterstitialBackend {
  static final instance = GoogleInterstitialBackend();

  @override
  bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<InterstitialHandle?> load(String unitId) async {
    if (!supported) return null;
    try {
      await MobileAds.instance.initialize().timeout(
        const Duration(seconds: 10),
      );
      await MobileAds.instance.setAppMuted(true);
      final result = Completer<InterstitialHandle?>();
      var expired = false;
      InterstitialAd.load(
        adUnitId: unitId,
        request: const AdRequest(nonPersonalizedAds: true),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (expired || result.isCompleted) {
              unawaited(ad.dispose().catchError((Object _) {}));
            } else {
              result.complete(_GoogleInterstitialHandle(ad));
            }
          },
          onAdFailedToLoad: (error) {
            if (kDebugMode) {
              debugPrint('Test interstitial unavailable (${error.code})');
            }
            if (!expired && !result.isCompleted) result.complete(null);
          },
        ),
      );
      return await result.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          expired = true;
          return null;
        },
      );
    } catch (_) {
      return null;
    }
  }
}

class _GoogleInterstitialHandle implements InterstitialHandle {
  _GoogleInterstitialHandle(this._ad);
  final InterstitialAd _ad;
  bool _disposed = false;

  @override
  Future<void> show() async {
    final finished = Completer<void>();
    void finish() {
      if (!finished.isCompleted) finished.complete();
    }

    _ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (_) => finish(),
      onAdFailedToShowFullScreenContent: (_, error) => finish(),
    );
    try {
      await _ad.show();
      await finished.future;
    } finally {
      dispose();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_ad.dispose().catchError((Object _) {}));
  }
}

/// One instance is passed from the completed workout to its share page.
/// It can attempt display only once, even if save and Back race each other.
class WorkoutInterstitialSession with WidgetsBindingObserver {
  WorkoutInterstitialSession._(this._entitlement, this._backend, this._unitId) {
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _entitlement.addListener(_onEntitlement);
    WidgetsBinding.instance.addObserver(this);
  }

  final AdsEntitlement _entitlement;
  final InterstitialBackend _backend;
  final String _unitId;
  InterstitialHandle? _ad;
  bool _disposed = false;
  bool _foreground = true;
  bool _attempted = false;
  bool get attempted => _attempted;

  static Future<WorkoutInterstitialSession?> afterSavedWorkout({
    required AdsConfig config,
    required AdsEntitlement entitlement,
    required TargetPlatform platform,
    InterstitialBackend? backend,
    SharedPreferences? preferences,
    WorkoutInterstitialPolicy policy = const WorkoutInterstitialPolicy(),
  }) async {
    final id = config.interstitialId(platform);
    final resolvedBackend = backend ?? GoogleInterstitialBackend.instance;
    if (id == null || entitlement.adFree || !resolvedBackend.supported) {
      return null;
    }
    final prefs = preferences ?? await SharedPreferences.getInstance();
    final eligible = await policy.recordCompletion(prefs);
    if (!eligible) return null;
    final session = WorkoutInterstitialSession._(
      entitlement,
      resolvedBackend,
      id,
    );
    session.preload();
    return session;
  }

  void preload() {
    if (_disposed || _entitlement.adFree || !_foreground) return;
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final ad = await _backend.load(_unitId);
      if (_disposed || _entitlement.adFree || !_foreground || _attempted) {
        ad?.dispose();
      } else {
        _ad = ad;
      }
    } catch (_) {
      // Ads are optional and must never affect saved workouts or navigation.
    }
  }

  Future<void> tryShow() async {
    if (_attempted || _disposed) return;
    _attempted = true;
    final ad = _ad;
    _ad = null;
    if (ad == null || _entitlement.adFree || !_foreground) {
      ad?.dispose();
      return;
    }
    try {
      await ad.show().timeout(const Duration(seconds: 30));
    } catch (_) {
      // A failed/missing native callback must not trap the user on this page.
    } finally {
      ad.dispose();
    }
  }

  void _onEntitlement() {
    if (_entitlement.adFree) {
      _ad?.dispose();
      _ad = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _ad?.dispose();
      _ad = null;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _entitlement.removeListener(_onEntitlement);
    WidgetsBinding.instance.removeObserver(this);
    _ad?.dispose();
    _ad = null;
  }
}
