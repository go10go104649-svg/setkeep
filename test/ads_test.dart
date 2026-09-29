import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/ads/ads_config.dart';
import 'package:setkeep/ads/banner_backend.dart';
import 'package:setkeep/ads/setkeep_banner_ad.dart';
import 'package:setkeep/main.dart' show HomeShell;

class FakeBanner implements BannerHandle {
  FakeBanner(double width) : size = Size(width, 60);
  @override
  final Size size;
  bool disposed = false;
  @override
  VoidCallback? onUnavailable;
  @override
  Widget build() =>
      const ColoredBox(color: Colors.grey, child: Text('TEST BANNER'));
  @override
  void dispose() => disposed = true;
}

class FakeBackend implements BannerBackend {
  @override
  bool supported = true;
  int calls = 0;
  bool fail = false;
  bool pending = false;
  late Completer<BannerHandle?> result;
  final requests = <BannerRequest>[];
  final ads = <FakeBanner>[];
  @override
  Future<BannerHandle?> load(
    int width,
    String id,
    BannerRequest request,
  ) async {
    calls++;
    requests.add(request);
    if (fail) throw StateError('offline');
    if (pending) {
      result = Completer<BannerHandle?>();
      return result.future;
    }
    final ad = FakeBanner(width.toDouble());
    ads.add(ad);
    return ad;
  }
}

void main() {
  test(
    'test IDs only, production/off/unknown/platform/trainer fail closed',
    () {
      const config = AdsConfig(generalApp: true);
      expect(
        config.bannerId(TargetPlatform.android),
        'ca-app-pub-3940256099942544/9214589741',
      );
      expect(
        config.bannerId(TargetPlatform.iOS),
        'ca-app-pub-3940256099942544/2435281174',
      );
      expect(config.bannerId(TargetPlatform.macOS), isNull);
      for (final mode in ['production', 'off', 'typo']) {
        expect(
          AdsConfig(
            generalApp: true,
            mode: mode,
          ).bannerId(TargetPlatform.android),
          isNull,
        );
      }
      expect(const AdsConfig().bannerId(TargetPlatform.android), isNull);
      final android = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      final ios = File('ios/Runner/Info.plist').readAsStringSync();
      expect(android, contains(AdsConfig.androidAppId));
      expect(ios, contains(AdsConfig.iosAppId));
      final trainer = File(
        'apps/setkeep_trainer/android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(trainer, contains('MobileAdsInitProvider" tools:node="remove"'));
      expect(trainer, isNot(contains('ca-app-pub-')));
    },
  );

  late AdsEntitlement entitlement;
  late FakeBackend backend;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    entitlement = AdsEntitlement();
    backend = FakeBackend();
  });
  tearDown(() => entitlement.dispose());
  Future<void> pump(
    WidgetTester t, {
    bool general = true,
    TargetPlatform platform = TargetPlatform.android,
    Widget? home,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        builder: (_, child) => AdsScope(
          config: AdsConfig(generalApp: general),
          entitlement: entitlement,
          backend: backend,
          child: child!,
        ),
        home:
            home ??
            const Scaffold(
              body: Column(children: [Text('HOME'), SetkeepBannerAd()]),
            ),
      ),
    );
    await t.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'adaptive slot fits $platform and disposes on entitlement change',
      (t) async {
        t.view.physicalSize = const Size(320, 568);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await pump(t, platform: platform);
        expect(find.text('TEST BANNER'), findsOneWidget);
        expect(backend.ads.single.size.width, 320);
        expect(t.takeException(), isNull);
        entitlement.adFree = true;
        await t.pumpAndSettle();
        expect(find.text('TEST BANNER'), findsNothing);
        expect(backend.ads.single.disposed, true);
        expect(backend.calls, 1);
      },
    );
  }
  testWidgets(
    'ad-free at entry creates no request; Trainer creates no request',
    (t) async {
      entitlement.adFree = true;
      await pump(t);
      expect(backend.calls, 0);
      entitlement.adFree = false;
      await pump(t, general: false);
      expect(backend.calls, 0);
      expect(find.text('TEST BANNER'), findsNothing);
      await t.pumpWidget(const MaterialApp(home: SetkeepBannerAd()));
      expect(find.text('TEST BANNER'), findsNothing);
    },
  );
  testWidgets(
    'offline failure collapses slot, leaves HOME usable, no retry on rebuild',
    (t) async {
      backend.fail = true;
      await pump(t);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('TEST BANNER'), findsNothing);
      expect(t.getSize(find.byType(SetkeepBannerAd)).height, 0);
      await t.pump(const Duration(minutes: 1));
      expect(backend.calls, 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('refresh failure removes a previously loaded banner', (t) async {
    await pump(t);
    expect(find.text('TEST BANNER'), findsOneWidget);
    backend.ads.single.onUnavailable!();
    await t.pumpAndSettle();
    expect(find.text('TEST BANNER'), findsNothing);
    expect(backend.ads.single.disposed, true);
    expect(t.getSize(find.byType(SetkeepBannerAd)).height, 0);
  });
  testWidgets('late load after ad-free transition is cancelled and disposed', (
    t,
  ) async {
    backend.pending = true;
    await pump(t);
    entitlement.adFree = true;
    await t.pumpAndSettle();
    expect(backend.requests.single.cancelled, true);
    final ad = FakeBanner(320);
    backend.result.complete(ad);
    await t.pumpAndSettle();
    expect(ad.disposed, true);
    expect(find.text('TEST BANNER'), findsNothing);
  });
  testWidgets('HOME only; tab, route and background remove ads', (t) async {
    await pump(t, home: const HomeShell());
    expect(find.text('TEST BANNER'), findsOneWidget);
    await t.tap(find.text('履歴').last);
    await t.pumpAndSettle();
    expect(find.text('TEST BANNER'), findsNothing);
    expect(backend.ads.first.disposed, true);
    await t.tap(find.text('ホーム').last);
    await t.pumpAndSettle();
    final context = t.element(find.byType(HomeShell));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('other route')),
      ),
    );
    await t.pumpAndSettle();
    expect(backend.ads.last.disposed, true);
    Navigator.of(t.element(find.text('other route'))).pop();
    await t.pumpAndSettle();
    expect(find.text('TEST BANNER'), findsOneWidget);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pumpAndSettle();
    expect(find.text('TEST BANNER'), findsNothing);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(backend.requests.last.cancelled, true);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
  });
}
