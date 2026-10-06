import '../constants/asset_paths.dart';
import 'body_composition.dart';

enum BodyTier { underweight, normal, overweight, obese }

/// BodyCompositionState (BMI state machine) -> the sprite tier / PNG.
/// `skinny` uses the art called body_underweight.png.
extension BodyCompositionTierX on BodyCompositionState {
  BodyTier get tier {
    switch (this) {
      case BodyCompositionState.skinny:
        return BodyTier.underweight;
      case BodyCompositionState.normal:
        return BodyTier.normal;
      case BodyCompositionState.overweight:
        return BodyTier.overweight;
      case BodyCompositionState.obese:
        return BodyTier.obese;
    }
  }

  /// e.g. assets/images/character/body_normal.png
  String get assetPath => '$kCharacterDir/${tier.assetName}';
}

extension BodyTierCompositionX on BodyTier {
  BodyCompositionState get composition {
    switch (this) {
      case BodyTier.underweight:
        return BodyCompositionState.skinny;
      case BodyTier.normal:
        return BodyCompositionState.normal;
      case BodyTier.overweight:
        return BodyCompositionState.overweight;
      case BodyTier.obese:
        return BodyCompositionState.obese;
    }
  }
}

extension BodyTierExt on BodyTier {
  String get label {
    switch (this) {
      case BodyTier.underweight: return 'Underweight';
      case BodyTier.normal:      return 'Normal';
      case BodyTier.overweight:  return 'Overweight';
      case BodyTier.obese:       return 'Obese';
    }
  }

  String get id {
    switch (this) {
      case BodyTier.underweight: return 'underweight';
      case BodyTier.normal:      return 'normal';
      case BodyTier.overweight:  return 'overweight';
      case BodyTier.obese:       return 'obese';
    }
  }

  /// Matches the exact filename under assets/images/character/.
  String get assetName {
    switch (this) {
      case BodyTier.underweight: return 'body_underweight.png';
      case BodyTier.normal:      return 'body_normal.png';
      case BodyTier.overweight:  return 'body_overweight.png';
      case BodyTier.obese:       return 'body_obese.png';
    }
  }

  static BodyTier fromId(String id) {
    switch (id) {
      case 'underweight': return BodyTier.underweight;
      case 'overweight':  return BodyTier.overweight;
      case 'obese':        return BodyTier.obese;
      default:             return BodyTier.normal;
    }
  }

  /// Standard medical BMI bands (shared with the check-in calculator in
  /// body_composition.dart, so there is ONE set of thresholds).
  static BodyTier fromBmi(double heightCm, double weightKg) {
    if (heightCm <= 0 || weightKg <= 0) return BodyTier.normal;
    return calculateBodyComposition(weightKg, heightCm).tier;
  }
}

// ───────────────────────── Gender routing ─────────────────────────

/// 'female' (any case) -> the female sheet; anything else (incl. null / old
/// accounts with no gender) -> the original male sheet.
bool isFemaleGender(String? gender) => gender?.trim().toLowerCase() == 'female';

/// Asset key of the body PNG for a gender + body-mass state.
///   female -> assets/images/character/female/body_<tier>.png
///   male   -> assets/images/character/body_<tier>.png
String bodyAssetFor(BodyTier tier, String? gender) {
  if (isFemaleGender(gender)) {
    return '$kFemaleCharacterDir/${tier.assetName}';
  }
  return '$kCharacterDir/${tier.assetName}';
}

/// Matches your real hair_*.png files exactly.
enum HairStyle { warriorSpiky, classicPompadour, wavyMane, longFlowing, shortCrop }

extension HairStyleExt on HairStyle {
  String get id {
    switch (this) {
      case HairStyle.warriorSpiky:      return 'warrior_spiky';
      case HairStyle.classicPompadour:  return 'classic_pompadour';
      case HairStyle.wavyMane:          return 'wavy_mane';
      case HairStyle.longFlowing:       return 'long_flowing';
      case HairStyle.shortCrop:         return 'short_crop';
    }
  }

  String get label {
    switch (this) {
      case HairStyle.warriorSpiky:      return 'Warrior Spiky';
      case HairStyle.classicPompadour:  return 'Classic Pompadour';
      case HairStyle.wavyMane:          return 'Wavy Mane';
      case HairStyle.longFlowing:       return 'Long Flowing';
      case HairStyle.shortCrop:         return 'Short Crop';
    }
  }

  /// Exact filename, matching your uploaded asset tree.
  String get assetFileName {
    switch (this) {
      case HairStyle.warriorSpiky:      return 'hair_01_warrior_spiky.png';
      case HairStyle.classicPompadour:  return 'hair_03_classic_pompadour.png';
      case HairStyle.wavyMane:          return 'hair_05_wavy_mane.png';
      case HairStyle.longFlowing:       return 'hair_07_long_flowing.png';
      case HairStyle.shortCrop:         return 'hair_14_short_crop.png';
    }
  }

  String get assetPath => '$kHairDir/$assetFileName';

  static HairStyle fromId(String id) {
    // tolerant: 'Wavy Mane' / 'wavy mane' / 'wavy_mane' all work
    switch (id.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_')) {
      case 'classic_pompadour': return HairStyle.classicPompadour;
      case 'wavy_mane':         return HairStyle.wavyMane;
      case 'long_flowing':      return HairStyle.longFlowing;
      case 'short_crop':        return HairStyle.shortCrop;
      default:                  return HairStyle.warriorSpiky;
    }
  }
}

/// Only one expression exists today (expression_01.png = neutral).
/// Add more cases here later as you add more face art.
enum FaceExpression { neutral }

extension FaceExpressionExt on FaceExpression {
  String get id {
    switch (this) {
      case FaceExpression.neutral: return 'neutral';
    }
  }

  String get assetFileName {
    switch (this) {
      case FaceExpression.neutral: return 'expression_01.png';
    }
  }

  String get assetPath => '$kFaceDir/$assetFileName';

  static FaceExpression fromId(String id) {
    switch (id) {
      default: return FaceExpression.neutral;
    }
  }
}

const List<String> kSkinTonePresets = [
  '#FFE0BD',
  '#F1C27D',
  '#E0AC69',
  '#C68642',
  '#8D5524',
  '#5C3317',
];

const List<String> kHairColorPresets = [
  '#1A1A1A',
  '#3B2415',
  '#8B5A2B',
  '#D2A679',
  '#E8C468',
  '#B33A1E',
  '#4A4A4A',
];

class CharacterProfile {
  final double? heightCm;
  final double? weightKg;
  final String skinTone;
  final HairStyle hairStyle;
  final String hairColor;
  final FaceExpression faceExpression;
  final bool created;

  /// 'male' | 'female' | null (set at sign-up, stored in users/{uid}.gender).
  final String? gender;

  const CharacterProfile({
    this.heightCm,
    this.weightKg,
    this.skinTone = '#E0AC69',
    this.hairStyle = HairStyle.shortCrop,
    this.hairColor = '#1A1A1A',
    this.faceExpression = FaceExpression.neutral,
    this.created = false,
    this.gender,
  });

  BodyTier get bodyTier {
    if (heightCm == null || weightKg == null) return BodyTier.normal;
    return BodyTierExt.fromBmi(heightCm!, weightKg!);
  }

  CharacterProfile copyWith({
    double? heightCm,
    double? weightKg,
    String? skinTone,
    HairStyle? hairStyle,
    String? hairColor,
    FaceExpression? faceExpression,
    bool? created,
    String? gender,
  }) {
    return CharacterProfile(
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      skinTone: skinTone ?? this.skinTone,
      hairStyle: hairStyle ?? this.hairStyle,
      hairColor: hairColor ?? this.hairColor,
      faceExpression: faceExpression ?? this.faceExpression,
      created: created ?? this.created,
      gender: gender ?? this.gender,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'height_cm': heightCm,
    'weight_kg': weightKg,
    'skin_tone': skinTone,
    'hair_style': hairStyle.id,
    'hair_color': hairColor,
    'face_expression': faceExpression.id,
    'body_tier': bodyTier.id,
    'character_created': created,
  };

  factory CharacterProfile.fromFirestore(Map<String, dynamic> data) {
    return CharacterProfile(
      heightCm: (data['height_cm'] as num?)?.toDouble(),
      weightKg: (data['weight_kg'] as num?)?.toDouble(),
      skinTone: data['skin_tone'] as String? ?? '#E0AC69',
      hairStyle: HairStyleExt.fromId(data['hair_style'] as String? ?? 'short_crop'),
      hairColor: data['hair_color'] as String? ?? '#1A1A1A',
      faceExpression: FaceExpressionExt.fromId(data['face_expression'] as String? ?? 'neutral'),
      created: data['character_created'] as bool? ?? false,
      gender: data['gender'] as String?,
    );
  }
}