// ═════════════════════════════════════════════════════════════════
//  BMI state machine
//
//  weight + height  ->  BMI  ->  BodyCompositionState
//
//  Pure Dart (no Flutter, no Firebase) so it is trivial to unit-test.
//  The enum -> sprite mapping lives in character_profile.dart
//  (BodyCompositionState.tier / .assetPath) to avoid a circular import.
// ═════════════════════════════════════════════════════════════════

/// Which unit system the numbers passed to the calculator are in.
///
///  * metric   : weight in kilograms, height in centimetres
///  * imperial : weight in pounds,    height in inches (total, not ft+in)
enum UnitSystem {
  metric('METRIC', 'kg', 'cm'),
  imperial('IMPERIAL', 'lb', 'in');

  final String label;
  final String weightUnit;
  final String heightUnit;
  const UnitSystem(this.label, this.weightUnit, this.heightUnit);

  /// Convert a weight typed in this system to kilograms.
  double weightToKg(double v) => this == metric ? v : v * kKgPerLb;

  /// Convert a height typed in this system to centimetres.
  double heightToCm(double v) => this == metric ? v : v * kCmPerInch;

  double kgToWeight(double kg) => this == metric ? kg : kg / kKgPerLb;
  double cmToHeight(double cm) => this == metric ? cm : cm / kCmPerInch;
}

const double kKgPerLb = 0.45359237;
const double kCmPerInch = 2.54;

/// BMI = 703 x lb / in^2 (imperial form of kg / m^2).
const double kBmiImperialFactor = 703.0;

// Standard WHO adult bands.
const double kBmiSkinnyBelow = 18.5; //     < 18.5        -> skinny
const double kBmiNormalBelow = 25.0; //     18.5 - 24.99  -> normal
const double kBmiOverweightBelow = 30.0; // 25 - 29.99    -> overweight, >= 30 obese

// Plausible human ranges. Anything outside is treated as a typo.
const double kMinHeightCm = 100;
const double kMaxHeightCm = 250;
const double kMinWeightKg = 25;
const double kMaxWeightKg = 300;

/// The four evolution forms of the hero, from lightest to heaviest.
enum BodyCompositionState {
  skinny('Skinny', '🦴'),
  normal('Normal', '💪'),
  overweight('Overweight', '🍔'),
  obese('Obese', '🛡️');

  final String label;
  final String emoji;
  const BodyCompositionState(this.label, this.emoji);

  /// Stable string id ('skinny' | 'normal' | 'overweight' | 'obese').
  String get id => name;

  /// How far this form is from the healthy "normal" form.
  /// skinny = 1, normal = 0, overweight = 1, obese = 2.
  int get distanceFromNormal {
    switch (this) {
      case BodyCompositionState.skinny:
        return 1;
      case BodyCompositionState.normal:
        return 0;
      case BodyCompositionState.overweight:
        return 1;
      case BodyCompositionState.obese:
        return 2;
    }
  }

  /// True when moving from [before] to this form is progress:
  /// Obese -> Overweight, Overweight -> Normal, Skinny -> Normal,
  /// Obese -> Normal, ... A sideways move (Skinny <-> Overweight) is NOT
  /// progress, and neither is drifting away from Normal.
  bool improvesOn(BodyCompositionState before) =>
      distanceFromNormal < before.distanceFromNormal;

  /// Accepts this enum's ids plus the legacy BodyTier ids
  /// ('underweight') and the old signup placeholder ('average').
  static BodyCompositionState fromId(String? id) {
    switch (id) {
      case 'skinny':
      case 'underweight':
        return BodyCompositionState.skinny;
      case 'overweight':
        return BodyCompositionState.overweight;
      case 'obese':
        return BodyCompositionState.obese;
      default:
        return BodyCompositionState.normal;
    }
  }

  /// Map a raw BMI score to a form.
  static BodyCompositionState fromBmi(double bmi) {
    if (bmi < kBmiSkinnyBelow) return BodyCompositionState.skinny;
    if (bmi < kBmiNormalBelow) return BodyCompositionState.normal;
    if (bmi < kBmiOverweightBelow) return BodyCompositionState.overweight;
    return BodyCompositionState.obese;
  }
}

/// Standard BMI score.
///
///   metric   : kg / (cm / 100)^2
///   imperial : 703 x lb / in^2
///
/// Throws [ArgumentError] for zero, negative or non-finite input, so a
/// bad value can never silently turn into "normal".
double calculateBmi(
  double weight,
  double height, {
  UnitSystem unit = UnitSystem.metric,
}) {
  if (!weight.isFinite || !height.isFinite || weight <= 0 || height <= 0) {
    throw ArgumentError('weight and height must be positive numbers '
        '(got weight=$weight, height=$height)');
  }
  switch (unit) {
    case UnitSystem.metric:
      final m = height / 100.0;
      return weight / (m * m);
    case UnitSystem.imperial:
      return kBmiImperialFactor * weight / (height * height);
  }
}

/// Weight + height in the given unit system -> the matching form.
///
///   calculateBodyComposition(70, 175)                           // kg, cm
///   calculateBodyComposition(154, 69, unit: UnitSystem.imperial) // lb, in
BodyCompositionState calculateBodyComposition(
  double weight,
  double height, {
  UnitSystem unit = UnitSystem.metric,
}) =>
    BodyCompositionState.fromBmi(calculateBmi(weight, height, unit: unit));

/// Returns null when the numbers are plausible, otherwise a short message
/// for the form. Checks are done in metric so both unit systems share them.
String? validateMeasurements(
  double? weight,
  double? height, {
  UnitSystem unit = UnitSystem.metric,
}) {
  if (height == null || !height.isFinite) return 'Enter your height';
  if (weight == null || !weight.isFinite) return 'Enter your weight';
  final cm = unit.heightToCm(height);
  final kg = unit.weightToKg(weight);
  if (cm < kMinHeightCm || cm > kMaxHeightCm) {
    return 'Height must be ${_fmt(unit.cmToHeight(kMinHeightCm))}-'
        '${_fmt(unit.cmToHeight(kMaxHeightCm))} ${unit.heightUnit}';
  }
  if (kg < kMinWeightKg || kg > kMaxWeightKg) {
    return 'Weight must be ${_fmt(unit.kgToWeight(kMinWeightKg))}-'
        '${_fmt(unit.kgToWeight(kMaxWeightKg))} ${unit.weightUnit}';
  }
  return null;
}

String _fmt(double v) => v.round().toString();

// ─────────────────────── text <-> number helpers ───────────────────────

/// Parse a typed number ("72", "72.5"). Returns null for junk.
double? parseNumber(String raw) => double.tryParse(raw.trim());

/// Parse an imperial height into TOTAL inches. Accepts
///   5'8   5' 8"   5 8   5-8   5'      -> feet + inches
///   68                                  -> plain number = inches
double? parseImperialHeightInches(String raw) {
  final s = raw.trim().replaceAll('"', '').replaceAll('’', "'");
  if (s.isEmpty) return null;
  final m = RegExp(r"^(\d+)\s*['\-\s]\s*(\d+(?:\.\d+)?)?$").firstMatch(s);
  if (m != null) {
    final feet = int.parse(m.group(1)!);
    final inches = double.tryParse(m.group(2) ?? '') ?? 0;
    return feet * 12 + inches;
  }
  return double.tryParse(s);
}

/// 172.7 cm -> 5'8
String formatImperialHeight(double cm) {
  final totalIn = cm / kCmPerInch;
  var feet = totalIn ~/ 12;
  var inches = (totalIn - feet * 12).round();
  if (inches == 12) {
    feet += 1;
    inches = 0;
  }
  return "$feet'$inches";
}

/// 72.0 -> "72", 72.5 -> "72.5"
String formatNumber(double v, {int decimals = 1}) {
  final s = v.toStringAsFixed(decimals);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}
