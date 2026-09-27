import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/exercise_form_catalog.dart';
import 'package:setkeep/exercise_media.dart';
import 'package:setkeep/main.dart';

void main() {
  test('requested guides use stable and distinct selectable identities', () {
    const additions = {
      'skull_crusher': '0024',
      'preacher_curl': '0022',
      'dumbbell_skull_crusher': '0150',
      'push_up_bar': '0234',
      'diamond_push_up': '1128',
      'incline_push_up': '1151',
      'decline_push_up': '1126',
      'v_bar_pushdown': '0139',
      'meadows_row': '0158',
      'gorilla_row': '0193',
      'bird_dog': '1111',
      'chest_supported_tbar_row': '0041',
    };
    for (final entry in additions.entries) {
      final template = exerciseTemplates.singleWhere(
        (e) => e.exerciseId == entry.key,
      );
      expect(template.name, isNotEmpty);
      expect(
        ExerciseMediaCatalog.forExerciseId(entry.key)?.providerAssetId,
        entry.value,
      );
      expect(ExerciseFormCatalog.byId[entry.key]!.assetPath, isNull);
    }
    expect(
      exerciseTemplates
          .singleWhere((e) => e.exerciseId == 'preacher_curl')
          .matchesQuery('プリチャーカール'),
      isTrue,
    );
    expect(
      ExerciseFormCatalog.canonicalId('dumbbell_skull_crusher'),
      isNot('skull_crusher'),
    );
    expect(
      ExerciseMediaCatalog.forExerciseId('machine_preacher_curl')
          ?.providerAssetId,
      '0159',
    );
    expect(
      ExerciseMediaCatalog.forExerciseId('t_bar_row')?.providerAssetId,
      '0206',
    );
  });

  test('home exercises record repetitions without external weight', () {
    for (final id in [
      'push_up_bar',
      'diamond_push_up',
      'incline_push_up',
      'decline_push_up',
      'bird_dog',
    ]) {
      final definition = ExerciseFormCatalog.byId[id]!;
      expect(definition.recordType, 'bodyweightReps');
      expect(definition.loadMode, 'bodyweight');
    }
    expect(
      ExerciseFormCatalog.byId['dumbbell_skull_crusher']!.recordType,
      'weightReps',
    );
  });

  test('equivalent gray videos preferred without changing exercise form', () {
    const gray = {
      'deadlift': '0032',
      'face_pull': '0030',
      'military_press': '0088',
      'glute_bridge': '1139',
      'cable_crunch': '0002',
    };
    for (final entry in gray.entries) {
      expect(
        ExerciseMediaCatalog.forExerciseId(entry.key)?.providerAssetId,
        entry.value,
      );
    }
    // Gray alternatives have a different posture, so keep the matching video.
    expect(
      ExerciseMediaCatalog.forExerciseId('dumbbell_shoulder_press')
          ?.providerAssetId,
      '0257',
    ); // seated, not standing
    expect(
      ExerciseMediaCatalog.forExerciseId('plank')?.providerAssetId,
      '0126',
    ); // forearms, not high plank
    expect(
      ExerciseMediaCatalog.forExerciseId('ab_wheel')?.providerAssetId,
      '0101',
    ); // kneeling, not standing
  });
}
