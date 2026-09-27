import 'package:flutter/services.dart';

import 'exercise_form_catalog.dart';

part 'vital_media_catalog.g.dart';

/// Optional media is keyed by SETKEEP's stable exercise ID, never the provider ID.
class ExerciseMedia {
  const ExerciseMedia({
    required this.exerciseId,
    required this.provider,
    required this.providerAssetId,
    required this.mediaType,
    required this.assetPath,
    this.thumbnailAssetPath,
    this.videoUrl,
    this.isActive = true,
  });

  final String exerciseId;
  final String provider;
  final String providerAssetId;
  final String mediaType;
  final String assetPath;
  final String? thumbnailAssetPath;
  final Uri? videoUrl;
  final bool isActive;
}

class ExerciseMediaCatalog {
  static List<ExerciseMedia> get entries =>
      List.unmodifiable(_vitalMedia.values);

  static ExerciseMedia? forExerciseId(String? exerciseId) {
    if (exerciseId == null) return null;
    final media = _vitalMedia[ExerciseFormCatalog.canonicalId(exerciseId)];
    return media?.isActive == true ? media : null;
  }

  static Future<bool> isAvailable(
    ExerciseMedia media, {
    AssetBundle? bundle,
  }) async {
    if (media.videoUrl != null) return true;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(
        bundle ?? rootBundle,
      );
      return manifest.listAssets().contains(media.assetPath);
    } catch (_) {
      return false;
    }
  }
}
