import 'support/signed_in_auth.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/design/app_colors.dart';
import 'package:setkeep/startup/startup_splash.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const androidLogo =
      'android/app/src/main/res/drawable-xxxhdpi/launch_logo.png';
  const iosLogo =
      'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png';

  testWidgets(
    'general startup reaches onboarding without an extra loading gate',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth(), showStartup: true));
      final splash = tester.widget(
        find.byWidgetPredicate((widget) => widget is StartupSplash),
      ) as StartupSplash;
      expect(splash.accent, AppColors.primaryGreen);
      await tester.pumpAndSettle();
      expect(find.text('ジムと一緒にトレーニングを記録'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('completed onboarding opens legal consent after startup', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    await tester.pumpWidget(const SetkeepApp(auth: SignedInTestAuth(), showStartup: true));
    await tester.pumpAndSettle();
    expect(find.text('利用規約を読む'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'progress waits for completed work and reaches 100 before route',
    (tester) async {
      final first = Completer<void>();
      final second = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: StartupSplash<String>(
            background: Colors.white,
            track: Colors.grey,
            accent: Colors.green,
            androidLogo: androidLogo,
            iosLogo: iosLogo,
            initialize: (progress, offline) async {
              await first.future;
              progress(0.5);
              await second.future;
              return 'ready';
            },
            destination: (_) => const Text('ready'),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const Key('startupProgressFill'))).width,
        0,
      );
      first.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('startupProgressFill'))).width,
        86,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('ready'), findsNothing);
      second.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('ready'), findsOneWidget);
    },
  );

  testWidgets('failure stays below 100 and can retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StartupSplash<String>(
          background: Colors.white,
          track: Colors.grey,
          accent: Colors.green,
          androidLogo: androidLogo,
          iosLogo: iosLogo,
          initialize: (progress, offline) async {
            calls++;
            progress(0.5);
            if (calls == 1) throw StateError('private error');
            return 'ready';
          },
          destination: (_) => const Text('ready'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('private error'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('startupProgressFill'))).width,
      86,
    );
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('ready'), findsOneWidget);
    expect(calls, 2);
  });
}
