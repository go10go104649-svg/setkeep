import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'gym_repository.dart';
import 'custom_gym_preference.dart';

class TrainingPlace {
  const TrainingPlace.home({this.notice})
    : store = null,
      manualName = null,
      storedCustomPlaceId = null;
  const TrainingPlace.store(this.store, {this.notice})
    : manualName = null,
      storedCustomPlaceId = null;
  const TrainingPlace.manual(
    this.manualName, {
    this.storedCustomPlaceId,
    this.notice,
  }) : store = null;
  final String? notice;
  final String? storedCustomPlaceId;
  String? get customPlaceId => manualName == null
      ? null
      : storedCustomPlaceId ?? CustomGymPreference.idFor(manualName!);
  final String? manualName;
  bool get isHome => store == null && manualName == null;
  final GymStore? store;
  String get name => store?.displayName ?? manualName ?? '自宅';
  String? get storeId => store?.id;
}

/// Account-local default, separate from legacy name-only preferences. Old names
/// and custom gyms remain intact; a name is never guessed into a store identity.
class TrainingPlacePreference {
  static String get _key {
    final user = SupabaseConfig.initialized
        ? Supabase.instance.client.auth.currentUser?.id
        : null;
    return 'training_place_v1_${user ?? 'guest'}';
  }

  static Future<TrainingPlace> load() async {
    final key = _key;
    final p = await SharedPreferences.getInstance();
    final value = p.getString(key);
    if (value == null) return const TrainingPlace.home();
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      final manual = json['manualName'];
      if (manual is String && manual.trim().isNotEmpty) {
        await CustomGymPreference.load();
        return TrainingPlace.manual(
          manual.trim(),
          storedCustomPlaceId: json['customPlaceId'] as String?,
        );
      }
      final store = json['store'];
      if (store is Map<String, dynamic>) {
        final parsed = GymStore.fromJson(store);
        if (parsed.id.isNotEmpty) {
          return TrainingPlace.store(parsed);
        }
      }
    } catch (_) {
      // A corrupt preference must not prevent recording a workout.
    }
    return const TrainingPlace.home();
  }

  static Future<void> save(TrainingPlace place) async {
    final key = _key;
    final p = await SharedPreferences.getInstance();
    if (!await p.setString(
      key,
      jsonEncode({
        'store': place.store?.toJson(),
        'manualName': place.manualName,
        'customPlaceId': place.customPlaceId,
      }),
    )) {
      throw StateError('利用場所を保存できませんでした');
    }
  }

  /// Explicit correction for the previously name-only Kanekin entry, requested
  /// by the user. This is not fuzzy matching or a general manual-place migration.
  /// Only remove old candidates after the verified DB store is registered.
  static Future<void> migrateKanekinPlace(GymRepository repository) async {
    const storeId = 'kanekin-fitness-gym:matsudo';
    const legacyNames = {
      'カネキンジム',
      'カネキンフィットネスジム',
      'KANEKIN FITNESS GYM',
      'KANEKIN FITNESS GYM 松戸店',
    };
    final preferences = await SharedPreferences.getInstance();
    await CustomGymPreference.load();
    final current = await load();
    final legacySelected = preferences.getString('selected_gym');
    final candidates = CustomGymPreference.gyms
        .where(legacyNames.contains)
        .toList();
    if (candidates.isEmpty &&
        !legacyNames.contains(current.manualName) &&
        !legacyNames.contains(legacySelected)) {
      return;
    }
    try {
      final stores = await repository.searchStores('カネキン');
      final matching = stores.where((s) => s.id == storeId && s.isSelectable);
      if (matching.isEmpty) return;
      final store = matching.single;
      await repository.register(store);
      if (legacyNames.contains(current.manualName) ||
          (preferences.getString(_key) == null &&
              legacyNames.contains(legacySelected))) {
        await save(TrainingPlace.store(store));
      }
      await CustomGymPreference.replaceAll(
        CustomGymPreference.gyms
            .where((name) => !legacyNames.contains(name))
            .toList(),
      );
      if (legacyNames.contains(legacySelected)) {
        await preferences.remove('selected_gym');
      }
    } catch (_) {
      // Retry on next load; offline users keep their original place data.
    }
  }

  static Future<TrainingPlace> forNewWorkout() async {
    final current = await load();
    if (current.storeId == null) return reconcile(const []);
    try {
      final repo = GymServices.repository;
      final registered = await repo.registered();
      if (!registered.any((s) => s.id == current.storeId)) {
        await save(const TrainingPlace.home());
        return const TrainingPlace.home();
      }
      final store = await repo.storeById(current.storeId!);
      if (store != null && store.isSelectable) {
        final fresh = TrainingPlace.store(store);
        await save(fresh);
        return fresh;
      }
      if (store != null) {
        await save(TrainingPlace.store(store));
        return TrainingPlace.home(
          notice:
              '${store.displayName}は${store.statusLabel}のため、今回は自宅で開始します。いつもの場所の設定は保持しています。',
        );
      }
      await save(const TrainingPlace.home());
      return const TrainingPlace.home();
    } catch (_) {
      // A temporary connection failure is not evidence of deletion.
      return current.store?.isSelectable == true
          ? TrainingPlace.store(
              current.store,
              notice: '店舗の最新の営業状況を確認できませんでした。必要に応じて場所を変更してください。',
            )
          : TrainingPlace.home(notice: 'いつもの場所は現在選択できません。設定は保持しています。');
    }
  }

  static Future<TrainingPlace> reconcile(List<GymStore> registered) async {
    final current = await load();
    if (current.manualName != null) {
      await CustomGymPreference.load();
      final id = current.customPlaceId;
      for (final name in CustomGymPreference.gyms) {
        if (id != null && CustomGymPreference.idFor(name) == id) {
          final fresh = TrainingPlace.manual(name, storedCustomPlaceId: id);
          await save(fresh);
          return fresh;
        }
      }
      await save(const TrainingPlace.home());
      return const TrainingPlace.home();
    }
    if (current.storeId == null) return current;
    for (final store in registered) {
      if (store.id == current.storeId) {
        final fresh = TrainingPlace.store(store);
        await save(fresh);
        return fresh;
      }
    }
    const home = TrainingPlace.home();
    await save(home);
    return home;
  }
}
