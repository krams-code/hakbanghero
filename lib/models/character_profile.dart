// lib/models/character_profile.dart

enum BodyTier { slim, average, powerhouse }

extension BodyTierExt on BodyTier {
  String get label {
    switch (this) {
      case BodyTier.slim:       return 'Slim';
      case BodyTier.average:    return 'Average';
      case BodyTier.powerhouse: return 'Powerhouse';
    }
  }

  String get id {
    switch (this) {
      case BodyTier.slim:       return 'slim';
      case BodyTier.average:    return 'average';
      case BodyTier.powerhouse: return 'powerhouse';
    }
  }

  static BodyTier fromId(String id) {
    switch (id) {
      case 'slim':       return BodyTier.slim;
      case 'powerhouse':  return BodyTier.powerhouse;
      default:            return BodyTier.average;
    }
  }

  /// BMI-based tier calculation.
  /// Standard BMI bands, repurposed as game body tiers.
  static BodyTier fromBmi(double heightCm, double weightKg) {
    if (heightCm <= 0 || weightKg <= 0) return BodyTier.average;
    final heightM = heightCm / 100.0;
    final bmi = weightKg / (heightM * heightM);
    if (bmi < 18.5) return BodyTier.slim;
    if (bmi < 25.0) return BodyTier.average;
    return BodyTier.powerhouse;
  }
}

enum HairStyle { short, long, buzz, ponytail }

extension HairStyleExt on HairStyle {
  String get id {
    switch (this) {
      case HairStyle.short:    return 'short';
      case HairStyle.long:     return 'long';
      case HairStyle.buzz:     return 'buzz';
      case HairStyle.ponytail: return 'ponytail';
    }
  }

  String get label {
    switch (this) {
      case HairStyle.short:    return 'Short';
      case HairStyle.long:     return 'Long';
      case HairStyle.buzz:     return 'Buzz Cut';
      case HairStyle.ponytail: return 'Ponytail';
    }
  }

  static HairStyle fromId(String id) {
    switch (id) {
      case 'long':     return HairStyle.long;
      case 'buzz':      return HairStyle.buzz;
      case 'ponytail':  return HairStyle.ponytail;
      default:          return HairStyle.short;
    }
  }
}

/// Preset skin tone swatches (hex strings), roughly Fitzpatrick-inspired range.
const List<String> kSkinTonePresets = [
  '#FFE0BD', // fair
  '#F1C27D', // light
  '#E0AC69', // medium-light
  '#C68642', // medium
  '#8D5524', // medium-dark
  '#5C3317', // dark
];

/// Preset hair color swatches (hex strings).
const List<String> kHairColorPresets = [
  '#1A1A1A', // black
  '#3B2415', // dark brown
  '#8B5A2B', // brown
  '#D2A679', // dirty blonde
  '#E8C468', // blonde
  '#B33A1E', // auburn/red
  '#4A4A4A', // grey/silver
];

class CharacterProfile {
  final double? heightCm;
  final double? weightKg;
  final String skinTone;    // hex
  final HairStyle hairStyle;
  final String hairColor;   // hex
  final bool created;

  const CharacterProfile({
    this.heightCm,
    this.weightKg,
    this.skinTone = '#E0AC69',
    this.hairStyle = HairStyle.short,
    this.hairColor = '#1A1A1A',
    this.created = false,
  });

  BodyTier get bodyTier {
    if (heightCm == null || weightKg == null) return BodyTier.average;
    return BodyTierExt.fromBmi(heightCm!, weightKg!);
  }

  CharacterProfile copyWith({
    double? heightCm,
    double? weightKg,
    String? skinTone,
    HairStyle? hairStyle,
    String? hairColor,
    bool? created,
  }) {
    return CharacterProfile(
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      skinTone: skinTone ?? this.skinTone,
      hairStyle: hairStyle ?? this.hairStyle,
      hairColor: hairColor ?? this.hairColor,
      created: created ?? this.created,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'height_cm': heightCm,
    'weight_kg': weightKg,
    'skin_tone': skinTone,
    'hair_style': hairStyle.id,
    'hair_color': hairColor,
    'body_tier': bodyTier.id,
    'character_created': created,
  };

  factory CharacterProfile.fromFirestore(Map<String, dynamic> data) {
    return CharacterProfile(
      heightCm: (data['height_cm'] as num?)?.toDouble(),
      weightKg: (data['weight_kg'] as num?)?.toDouble(),
      skinTone: data['skin_tone'] as String? ?? '#E0AC69',
      hairStyle: HairStyleExt.fromId(data['hair_style'] as String? ?? 'short'),
      hairColor: data['hair_color'] as String? ?? '#1A1A1A',
      created: data['character_created'] as bool? ?? false,
    );
  }
}