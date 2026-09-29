import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep/gym/gym_pages.dart';
import 'package:setkeep/gym/gym_repository.dart';

import 'gym_integration_test.dart' show FakeGyms;

class _ChainRepo extends FakeGyms {
  @override
  Future<Map<String, String>> chains() async => {
    'world-plus-gym': 'WORLD+GYM',
    'kanekin-fitness-gym': 'KANEKIN FITNESS GYM',
    'fit-place24': 'FIT PLACE24',
    'auns-gym': "AUN'S GYM",
  };

  @override
  Future<List<GymStore>> search(String query, {int offset = 0}) async => [
    const GymStore(
      id: 'auns-store',
      chainId: 'auns-gym',
      chainName: "AUN'S GYM",
      name: 'テスト店',
    ),
    const GymStore(
      id: 'kanekin-store',
      chainId: 'kanekin-fitness-gym',
      chainName: 'KANEKIN FITNESS GYM',
      name: '松戸店',
    ),
  ];
}

void main() {
  test('chain names sort by Latin alphabet then Japanese gojuon', () {
    final names = sortedGymChainOptions({
      'world': 'WORLD+GYM',
      'fit-place': 'FIT PLACE24',
      'fit-easy': 'FIT-EASY',
      'fast': 'FASTGYM24',
      'fit24': 'FiT24',
      'auns': "AUN'S GYM",
      'kana-e': 'エニタイムフィットネス',
      'kana-a': 'あさひジム',
      'kanekin-fitness-gym': 'KANEKIN FITNESS GYM',
    }).map((entry) => entry.value).toList();
    expect(names, [
      "AUN'S GYM",
      'FASTGYM24',
      'FiT24',
      'FIT-EASY',
      'FIT PLACE24',
      'WORLD+GYM',
      'あさひジム',
      'エニタイムフィットネス',
    ]);
  });

  testWidgets('filter omits KANEKIN option without hiding its store', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    GymServices.override = _ChainRepo();
    addTearDown(() => GymServices.override = null);
    await tester.pumpWidget(const MaterialApp(home: GymStoreSearchPage()));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('selectGymStorekanekin-store')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('gymChainFilter')));
    await tester.pumpAndSettle();
    expect(find.text('KANEKIN FITNESS GYM'), findsNothing);
    await tester.tap(find.text("AUN'S GYM").last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selectGymStoreauns-store')), findsOneWidget);
    expect(find.byKey(const Key('selectGymStorekanekin-store')), findsNothing);
  });
}
