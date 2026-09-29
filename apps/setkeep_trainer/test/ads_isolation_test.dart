import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/ads/setkeep_banner_ad.dart';
import 'package:setkeep_trainer/main.dart';

import 'trainer_app_test.dart' show FakeAuth, FakeRepository;

void main() {
  testWidgets('TRAINER never opts into ads across its main destinations', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final auth = FakeAuth();
    addTearDown(auth.events.close);
    await t.pumpWidget(TrainerApp(auth: auth, repository: FakeRepository()));
    await t.pumpAndSettle();
    void noAds() {
      expect(find.byType(AdsScope), findsNothing);
      expect(find.byType(SetkeepBannerAd), findsNothing);
    }

    noAds();
    final destinations = t
        .widget<NavigationBar>(find.byType(NavigationBar))
        .destinations;
    for (final destination in destinations.cast<NavigationDestination>()) {
      await t.tap(find.text(destination.label).last);
      await t.pumpAndSettle();
      noAds();
      expect(t.takeException(), isNull);
    }
  });
}
