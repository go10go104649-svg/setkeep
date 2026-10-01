import 'package:flutter/foundation.dart';

/// Test-only foundation. Unknown/off/production modes fail closed until the
/// native IDs, consent flow and release privacy review are implemented together.
class AdsConfig {
  const AdsConfig({this.generalApp = false, this.mode = buildMode});
  static const buildMode = String.fromEnvironment(
    'SETKEEP_ADS_MODE',
    defaultValue: 'test',
  );
  final bool generalApp;
  final String mode;

  // Google sample App IDs; mirrored in the general app's manifest / Info.plist.
  static const androidAppId = 'ca-app-pub-3940256099942544~3347511713';
  static const iosAppId = 'ca-app-pub-3940256099942544~1458002511';
  String? bannerId(TargetPlatform platform) {
    if (!generalApp || mode != 'test') return null;
    return switch (platform) {
      TargetPlatform.android => 'ca-app-pub-3940256099942544/9214589741',
      TargetPlatform.iOS => 'ca-app-pub-3940256099942544/2435281174',
      _ => null,
    };
  }

  String? interstitialId(TargetPlatform platform) {
    if (!generalApp || mode != 'test') return null;
    return switch (platform) {
      TargetPlatform.android => 'ca-app-pub-3940256099942544/1033173712',
      TargetPlatform.iOS => 'ca-app-pub-3940256099942544/4411468910',
      _ => null,
    };
  }
}

/// Future verified purchase entitlement connects here, independently of Premium.
/// No purchase, billing or local "paid" toggle is exposed to users yet.
class AdsEntitlement extends ValueNotifier<bool> {
  AdsEntitlement({bool adFree = false}) : super(adFree);
  bool get adFree => value;
  set adFree(bool enabled) => value = enabled;
}

final setkeepAdsEntitlement = AdsEntitlement();
