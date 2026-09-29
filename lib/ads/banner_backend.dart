import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class BannerRequest {
  bool cancelled = false;
  VoidCallback? onCancel;
  void cancel() {
    cancelled = true;
    onCancel?.call();
    onCancel = null;
  }
}

abstract class BannerHandle {
  set onUnavailable(VoidCallback? callback);
  Size get size;
  Widget build();
  void dispose();
}

abstract class BannerBackend {
  bool get supported;
  Future<BannerHandle?> load(int width, String unitId, BannerRequest request);
}

class GoogleBannerBackend implements BannerBackend {
  static final instance = GoogleBannerBackend();
  Future<bool>? _ready;
  @override
  bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<bool> _initialize() async {
    try {
      await MobileAds.instance.initialize().timeout(
        const Duration(seconds: 10),
      );
      await MobileAds.instance.setAppMuted(true);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<BannerHandle?> load(
    int width,
    String unitId,
    BannerRequest request,
  ) async {
    if (!supported || request.cancelled) return null;
    if (!await (_ready ??= _initialize().timeout(
          const Duration(seconds: 12),
          onTimeout: () => false,
        )) ||
        request.cancelled) {
      return null;
    }
    _GoogleBanner? handle;
    try {
      final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width)
          .timeout(const Duration(seconds: 5));
      if (size == null || request.cancelled) return null;
      final result = Completer<BannerHandle?>();
      void finish(BannerHandle? value) {
        if (!result.isCompleted) result.complete(value);
      }

      final ad = BannerAd(
        size: size,
        adUnitId: unitId,
        request: const AdRequest(nonPersonalizedAds: true),
        listener: BannerAdListener(
          onAdLoaded: (_) => finish(request.cancelled ? null : handle),
          onAdFailedToLoad: (_, error) {
            if (kDebugMode) {
              debugPrint('Test banner unavailable (${error.code})');
            }
            handle?.onUnavailable?.call();
            handle?.dispose();
            finish(null);
          },
        ),
      );
      handle = _GoogleBanner(ad);
      request.onCancel = () {
        handle?.dispose();
        finish(null);
      };
      await ad.load().timeout(const Duration(seconds: 5));
      return await result.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          handle?.dispose();
          return null;
        },
      );
    } catch (_) {
      handle?.dispose();
      return null;
    }
  }
}

class _GoogleBanner implements BannerHandle {
  _GoogleBanner(this.ad);
  final BannerAd ad;
  @override
  VoidCallback? onUnavailable;
  bool _disposed = false;
  @override
  Size get size => Size(ad.size.width.toDouble(), ad.size.height.toDouble());
  @override
  Widget build() => AdWidget(ad: ad);
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    onUnavailable = null;
    unawaited(ad.dispose().catchError((Object _) {}));
  }
}
