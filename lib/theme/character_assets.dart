/// Layered SVG character assets, keyed by body tier.
/// Skin tone and hair color are applied via string replacement of the
/// {skin} and {hair} placeholder tokens — no separate files needed per color.
library character_assets;

class CharacterAssets {
  CharacterAssets._();

  // ── Body base shapes per tier ──────────────────────────────────
  // Simple, clean vector silhouettes matching the app's existing
  // hero-sprite aesthetic (see EquipmentScreen's _HeroSpritePainter).
  static String bodySvg(String tierId) {
    switch (tierId) {
      case 'slim':
        return _bodySlim;
      case 'powerhouse':
        return _bodyPowerhouse;
      default:
        return _bodyAverage;
    }
  }

  static String hairSvg(String styleId) {
    switch (styleId) {
      case 'long':
        return _hairLong;
      case 'buzz':
        return _hairBuzz;
      case 'ponytail':
        return _hairPonytail;
      default:
        return _hairShort;
    }
  }

  // Renders a body SVG string with the given skin tone hex substituted.
  static String renderBody(String tierId, String skinHex) {
    return bodySvg(tierId).replaceAll('{skin}', skinHex);
  }

  // Renders a hair SVG string with the given hair color hex substituted.
  static String renderHair(String styleId, String hairHex) {
    return hairSvg(styleId).replaceAll('{hair}', hairHex);
  }

  // ── Slim body ───────────────────────────────────────────────────
  static const _bodySlim = '''
<svg viewBox="0 0 120 220" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="60" cy="34" rx="20" ry="22" fill="{skin}"/>
  <path d="M46 52 L42 100 L52 150 L48 210 L60 210 L64 150 L60 100 L74 150 L70 210 L82 210 L78 150 L88 100 L84 52 Z" fill="{skin}"/>
  <path d="M40 60 L26 100 L32 108 L46 72 Z" fill="{skin}"/>
  <path d="M80 60 L94 100 L88 108 L74 72 Z" fill="{skin}"/>
</svg>
''';

  // ── Average body ────────────────────────────────────────────────
  static const _bodyAverage = '''
<svg viewBox="0 0 120 220" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="60" cy="34" rx="21" ry="23" fill="{skin}"/>
  <path d="M40 52 L36 102 L50 152 L46 210 L60 210 L66 152 L60 102 L78 152 L74 210 L88 210 L84 152 L96 102 L92 52 Z" fill="{skin}"/>
  <path d="M38 60 L22 104 L30 112 L46 74 Z" fill="{skin}"/>
  <path d="M82 60 L98 104 L90 112 L74 74 Z" fill="{skin}"/>
</svg>
''';

  // ── Powerhouse body ─────────────────────────────────────────────
  static const _bodyPowerhouse = '''
<svg viewBox="0 0 120 220" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="60" cy="34" rx="22" ry="24" fill="{skin}"/>
  <path d="M32 52 L26 106 L48 156 L42 210 L60 210 L70 156 L60 106 L84 156 L78 210 L96 210 L90 156 L106 106 L100 52 Z" fill="{skin}"/>
  <path d="M34 58 L14 108 L24 118 L44 76 Z" fill="{skin}"/>
  <path d="M86 58 L108 108 L96 118 L76 76 Z" fill="{skin}"/>
</svg>
''';

  // ── Hair styles ─────────────────────────────────────────────────
  static const _hairShort = '''
<svg viewBox="0 0 120 220" xmlns="http://www.w3.org/2000/svg">
  <path d="M60 10 C44 10 34 22 34 36 C34 40 35 44 36 47 L84 47 C85 44 86 40 86 36 C86 22 76 10 60 10 Z" fill="{hair}"/>
</svg>
''';

  static const _hairLong = '''
<svg viewBox="0 0 120 220" xmlns="http://www.w3.org/2000/svg">
  <path d="M60 8 C42 8 30 22 30 38 C30 60 34 80 38 95 L48 95 L46 50 L52 48 L56 95 L64 95 L68 48 L74 50 L72 95 L82 95 C86 80 90 60 90 38 C90 22 78 8 60 8 Z" fill="{hair}"/>
</svg>
''';

  static const _hairBuzz = '''
<svg viewBox="0 0 120 220" xmlns="http://www.w3.org/2000/svg">
  <path d="M60 12 C47 12 38 22 37 33 L83 33 C82 22 73 12 60 12 Z" fill="{hair}"/>
</svg>
''';

  static const _hairPonytail = '''
<svg viewBox="0 0 120 220" xmlns="http://www.w3.org/2000/svg">
  <path d="M60 10 C44 10 34 22 34 36 C34 40 35 44 36 47 L84 47 C85 44 86 40 86 36 C86 22 76 10 60 10 Z" fill="{hair}"/>
  <path d="M84 40 C94 44 100 58 96 74 C93 86 88 92 88 92 L82 88 C82 88 87 80 88 70 C89 58 84 48 78 44 Z" fill="{hair}"/>
</svg>
''';
  // ── Gear item layers, keyed by exact item name ─────────────────
  static const Map<String, String> _gearSvgByName = {
    'Iron Sword': _gearIronSword,
    'Phantom Blade': _gearPhantomBlade,
    'Verdant Blade': _gearVerdantBlade,
    'Shadow Crown': _gearShadowCrown,
    'Leather Hood': _gearLeatherHood,
    'Forest Plate': _gearForestPlate,
    'Shadow Cloak': _gearShadowCloak,
    'Windrunner Treads': _gearWindrunnerTreads,
    'Storm Boots': _gearStormBoots,
    'Arcane Ring': _gearArcaneRing,
    'Divine Gauntlet': _gearDivineGauntlet,
  };

  /// Returns the visual layer for a gear item, or null if it has no
  /// art yet (falls back to stat-only, invisible on the character).
  static String? gearSvg(String itemName) => _gearSvgByName[itemName];

  static const _gearIronSword = '''
<svg viewBox="0 0 120 220" xmlns="http://www.w3.org/2000/svg">
  <rect x="90" y="95" width="6" height="55" rx="2" fill="#B0B0B0"/>
  <rect x="84" y="93" width="18" height="6" rx="2" fill="#8A8A8A"/>
  <rect x="90" y="148" width="6" height="10" fill="#5A3A1A"/>
</svg>
''';

  static const _gearPhantomBlade = '''
<svg viewBox="0 0 120 220" xmlns="http://www.w3.org/2000/svg">
  <rect x="90" y="90" width="7" height="62" rx="3" fill="#4A2E6B"/>
  <rect x="82" y="88" width="22" height="6" rx="2" fill="#2E1A45"/>
  <rect x="90" y="150" width="7" height="10" fill="#1A1025"/>
</svg>
''';

  static const _gearVerdantBlade = '''
<svg viewBox="0 0 120 220" xmlns="http://www.w3.org/2000/svg">
  <rect x="90" y="88" width="7" height="64" rx="3" fill="#4CAF50"/>
  <rect x="82" y="86" width="22" height="6" rx="2" fill="#2E7D32"/>
  <rect x="90" y="150" width="7" height="10" fill="#1B4D1B"/>
</svg>
''';

  static const _gearShadowCrown = '''
<svg viewBox="0 0 120 220" xmlns="http://www.w3.org/2000/svg">
  <path d="M40 32 L46 14 L52 28 L60 10 L68 28 L74 14 L80 32 Z" fill="#3A1A4A"/>
  <rect x="40" y="30" width="40" height="8" rx="2" fill="#2A0F38"/>
</svg>
''';

  static const _gearLeatherHood = '''
<svg viewBox="0 0 120 220" xmlns="http://www.w3.org/2000/svg">
  <path d="M60 6 C42 6 32 20 32 36 C32 42 34 47 36 50 L84 50 C86 47 88 42 88 36 C88 20 78 6 60 6 Z" fill="#6B4226"/>
  <ellipse cx="60" cy="36" rx="16" ry="18" fill="#3A2113"/>
</svg>
''';

  static const _gearForestPlate = '''
<svg viewBox="0 0 120 220" xmlns="http://www.w3.org/2000/svg">
  <path d="M40 52 L38 100 L60 108 L82 100 L80 52 L60 60 Z" fill="#2E7D32"/>
  <rect x="56" y="60" width="8" height="40" fill="#1B4D1B"/>
</svg>
''';

  static const _gearShadowCloak = '''
<svg viewBox="0 0 120 220" xmlns="http://www.w3.org/2000/svg">
  <path d="M36 50 L24 140 L44 135 L48 60 L60 66 L72 60 L76 135 L96 140 L84 50 L60 58 Z" fill="#241033" fill-opacity="0.9"/>
</svg>
''';

  static const _gearWindrunnerTreads = '''
<svg viewBox="0 0 120 220" xmlns="http://www.w3.org/2000/svg">
  <path d="M44 188 L40 208 L58 208 L56 188 Z" fill="#0288D1"/>
  <path d="M64 188 L62 208 L80 208 L76 188 Z" fill="#0288D1"/>
  <path d="M34 194 L20 188 L34 202 Z" fill="#B3E5FC"/>
  <path d="M86 194 L100 188 L86 202 Z" fill="#B3E5FC"/>
</svg>
''';

  static const _gearStormBoots = '''
<svg viewBox="0 0 120 220" xmlns="http://www.w3.org/2000/svg">
  <path d="M44 188 L40 208 L58 208 L56 188 Z" fill="#546E7A"/>
  <path d="M64 188 L62 208 L80 208 L76 188 Z" fill="#546E7A"/>
  <path d="M58 190 L52 200 L58 200 L54 210 L66 196 L60 196 L64 190 Z" fill="#FFEB3B"/>
</svg>
''';

  static const _gearArcaneRing = '''
<svg viewBox="0 0 120 220" xmlns="http://www.w3.org/2000/svg">
  <circle cx="30" cy="112" r="5" fill="none" stroke="#2196F3" stroke-width="2.5"/>
  <circle cx="30" cy="112" r="2" fill="#64B5F6"/>
</svg>
''';

  static const _gearDivineGauntlet = '''
<svg viewBox="0 0 120 220" xmlns="http://www.w3.org/2000/svg">
  <rect x="20" y="102" width="16" height="20" rx="4" fill="#FFD700"/>
  <rect x="88" y="102" width="16" height="20" rx="4" fill="#FFD700"/>
</svg>
''';
}