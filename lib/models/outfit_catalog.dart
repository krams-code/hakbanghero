import '../constants/asset_paths.dart';

// ═════════════════════════════════════════════════════════════════════════
//  Outfit ids, starter pack and body-matched clothing paths
//
//  Every body size has its OWN clothing PNG (286x512), so clothes are never
//  scaled by code:
//
//     female:  assets/images/character/female/clothes/<stem>_<bodyType>.png
//              e.g. .../female/clothes/starter_set_obese.png
//     male:    assets/images/character/clothes/outfit_01.png   (one-size art,
//              fitted by LayerFit as before)
//
//  <bodyType> = underweight | normal | overweight | obese
// ═════════════════════════════════════════════════════════════════════════

/// Female per-body clothing folder.
const String kFemaleClothesDir = '$kFemaleCharacterDir/clothes';

/// The free starting outfit (white tank top set).
const String kStarterOutfitId = 'outfit_01_default_starter_set';

/// The file stem used by [kStarterOutfitId]: `starter_set_<bodyType>.png`.
const String kStarterOutfitStem = 'starter_set';

/// Everything a brand-new hero owns / wears. Written to Firestore at sign-up
/// (and again when the hero is created, so it can never be missing).
class StarterPack {
  const StarterPack._();

  /// Default hair style. (HairStyle id for "Wavy Mane".)
  static const String activeHair = 'wavy_mane';

  /// Default face. (Parsed by FaceExpressionExt, which has one expression.)
  static const String activeExpression = 'expression_01_default_neutral';

  /// Default outfit: the white tank-top set.
  static const String activeOutfit = kStarterOutfitId;

  /// Hair colours offered during onboarding (also free in the shop):
  /// Black, Brown, Blonde.
  static const List<String> hairColors = ['#1A1A1A', '#3B2415', '#E8C468'];

  /// Item ids every hero owns from minute one.
  static const List<String> ownedItems = [
    'wavy_mane',
    'neutral',
    kStarterOutfitId,
  ];

  /// Fields merged into users/{uid} (sign-up + create-hero).
  static Map<String, dynamic> toFirestore() => {
        'hair_style': activeHair,
        'face_expression': activeExpression,
        'equipped_clothes': [activeOutfit],
      };
}

/// Maps old / alias ids onto the one canonical id, so accounts created
/// before the starter pack ('outfit_01') keep working.
String normalizeOutfitId(String id) {
  final k = id.trim();
  if (k == 'outfit_01' || k == kStarterOutfitStem || k == kStarterOutfitId) {
    return kStarterOutfitId;
  }
  return k;
}

/// 'skinny' / 'underweight' -> 'underweight'; unknown -> 'normal'.
String canonicalBodyType(String bodyType) {
  switch (bodyType.trim().toLowerCase()) {
    case 'skinny':
    case 'underweight':
      return 'underweight';
    case 'overweight':
      return 'overweight';
    case 'obese':
      return 'obese';
    default:
      return 'normal'; // 'normal', 'average', ''
  }
}

/// One-size male clothing art (id -> asset key).
const Map<String, String> kMaleClothesCatalog = {
  kStarterOutfitId: '$kClothesDir/outfit_01.png',
  'outfit_01': '$kClothesDir/outfit_01.png', // legacy id
};

/// The clothing PNG for a body type + outfit. Returns '' for "no outfit".
///
///   female + starter set + obese  -> assets/images/character/female/clothes/starter_set_obese.png
///   female + starter set + normal -> assets/images/character/female/clothes/starter_set_normal.png
///   male                          -> the one-size male art
///
/// A full asset key (starts with `assets/`) is returned untouched.
String clothesAssetFor(String bodyType, String outfitId, {String? gender}) {
  final raw = outfitId.trim();
  if (raw.isEmpty) return '';
  if (raw.startsWith('assets/')) return raw;

  final id = normalizeOutfitId(raw);

  if (gender?.trim().toLowerCase() == 'female') {
    final stem = id == kStarterOutfitId ? kStarterOutfitStem : id;
    return '$kFemaleClothesDir/${stem}_${canonicalBodyType(bodyType)}.png';
  }
  return kMaleClothesCatalog[id] ?? '';
}

/// Folder name used by the animated runner's gear frames
/// (assets/images/character/anim/<state>/gear_<this>/frame_XX.png).
/// The starter set keeps its original `outfit_01` frame folder.
String animGearId(String outfitId) {
  final id = normalizeOutfitId(outfitId);
  return id == kStarterOutfitId ? 'outfit_01' : id;
}
