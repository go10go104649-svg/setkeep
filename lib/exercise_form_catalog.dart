import 'exercise_form_catalog.g.dart';
import 'muscle_targets.dart';

/// Stable form identity is independent from legacy record names and asset paths.
class ExerciseFormDefinition {
  ExerciseFormDefinition(Map<String, Object?> value)
    : _value = Map.unmodifiable(value);
  final Map<String, Object?> _value;
  String get exerciseId => _value['exerciseId']! as String;
  String? get canonicalExerciseId => _value['canonicalExerciseId'] as String?;
  bool get selectable => _value['selectable'] as bool? ?? true;
  String? get englishName => _value['englishName'] as String?;
  String get exerciseName => _value['exerciseName']! as String;
  String get category => _value['category']! as String;
  String get modelId => _value['modelId']! as String;
  String get animationId => _value['animationId']! as String;
  String get equipmentLabel => _value['equipmentLabel'] as String? ?? 'マシン';
  List<String> get tags => (_value['tags'] as List? ?? const []).cast<String>();
  String get distanceUnit => _value['distanceUnit'] as String? ?? 'km';
  List<String>? get recordFields =>
      (_value['recordFields'] as List?)?.cast<String>();
  double? get startWeight => (_value['startWeight'] as num?)?.toDouble();
  int? get startReps => (_value['startReps'] as num?)?.toInt();
  String get equipmentId => _value['equipmentId']! as String;
  String get gripType => _value['gripType']! as String;
  String get movementVariant => _value['movementVariant']! as String;
  String get recordType => _value['recordType']! as String;
  String get loadMode => _value['loadMode']! as String;
  String get status => _value['status']! as String;
  String? get assetPath => _value['assetPath'] as String?;
  bool get isPreview =>
      status == 'authored' &&
      _value['previewEnabled'] == true &&
      (_value['review'] as Map?)?['staticPose'] == true &&
      assetPath != null;
  bool get available =>
      assetPath != null && (status == 'verified' || isPreview);
  double get animationSpeed => (_value['animationSpeed']! as num).toDouble();
  double get rangeOfMotion => (_value['rangeOfMotion']! as num).toDouble();
  List<String> get aliases => (_value['aliases']! as List).cast<String>();
  List<String> get primaryMuscles =>
      (_value['primaryMuscles']! as List).cast<String>();
  List<String> get secondaryMuscles =>
      (_value['secondaryMuscles']! as List).cast<String>();
  List<String> get primaryMuscleLabels =>
      primaryMuscles.map(_muscleLabel).toList();
  List<String> get secondaryMuscleLabels =>
      secondaryMuscles.map(_muscleLabel).toList();
  static String _muscleLabel(String id) {
    if (id == 'erectorSpinae') return '脊柱起立筋';
    if (id == 'lateralDeltoid') return '三角筋中部';
    return MuscleRegion.values.firstWhere((muscle) => muscle.name == id).label;
  }

  Map<String, Object?> get parameters =>
      Map<String, Object?>.from(_value['parameters']! as Map);
  Map<String, Object?>? get camera => _value['cameraPreset'] == 'legacy_press'
      ? null
      : {
          'position': _value['cameraAngle'],
          'target': _value['cameraTarget'],
          'scale': _value['cameraScale'],
        };
}

class ExerciseFormCatalog {
  static final entries = List<ExerciseFormDefinition>.unmodifiable(
    exerciseFormData.map(ExerciseFormDefinition.new),
  );
  static final Map<String, ExerciseFormDefinition> byId = {
    for (final item in entries) item.exerciseId: item,
  };

  // Identity/display compatibility is separate from the exact 3D asset lookup.
  // Unknown and custom IDs remain untouched; names never assign an identity.
  static String canonicalId(String id) => byId[id]?.canonicalExerciseId ?? id;
  static ExerciseFormDefinition? canonicalDefinition(String? id) =>
      id == null ? null : byId[canonicalId(id)];

  /// Names and aliases may be ambiguous. Only an explicit ID selects a variant.
  static final Map<String, List<ExerciseFormDefinition>> byName = _indexNames();
  static Map<String, List<ExerciseFormDefinition>> _indexNames() {
    final result = <String, List<ExerciseFormDefinition>>{};
    for (final entry in entries) {
      for (final name in {entry.exerciseName, ...entry.aliases}) {
        result.putIfAbsent(name, () => []).add(entry);
      }
    }
    return Map.unmodifiable(
      result.map(
        (k, v) => MapEntry(k, List<ExerciseFormDefinition>.unmodifiable(v)),
      ),
    );
  }

  static ExerciseFormDefinition? forName(String name) {
    final matches = byName[name];
    return matches?.length == 1 ? matches!.single : null;
  }

  static ExerciseFormDefinition? resolve(String? id, String legacyName) =>
      id != null ? byId[id] : forName(legacyName);
}

String exerciseIdentity(String? id, String legacyName) =>
    id != null && id.isNotEmpty
    ? 'id:${ExerciseFormCatalog.canonicalId(id)}'
    : 'legacy:$legacyName';

String canonicalExerciseIdentity(String identity) => identity.startsWith('id:')
    ? exerciseIdentity(identity.substring(3), '')
    : identity;

String exerciseDisplayName(
  String storedName, {
  String? exerciseId,
  String languageCode = 'ja',
}) {
  final form = ExerciseFormCatalog.canonicalDefinition(exerciseId);
  if (languageCode == 'en' && form?.englishName != null) {
    return form!.englishName!;
  }
  return form?.exerciseName ?? storedName;
}

bool usesAdditionalWeight(String storedName, {String? exerciseId}) =>
    ExerciseFormCatalog.resolve(exerciseId, storedName)?.loadMode ==
    'additional';

bool usesAssistanceWeight(String storedName, {String? exerciseId}) =>
    ExerciseFormCatalog.resolve(exerciseId, storedName)?.loadMode ==
    'assistance';
