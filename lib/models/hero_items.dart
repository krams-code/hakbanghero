import 'character_profile.dart' show BodyTier, BodyTierExt;
import 'hero_item_art.dart';
import 'hero_progress.dart';

/// Where an item is worn.
enum HeroSlot {
  head('HEAD', '\u{1F3A9}'),
  face('FACE', '\u{1F576}'),
  top('TOP', '\u{1F455}'),
  bottom('BOTTOM', '\u{1FA73}'),
  shoes('SHOES', '\u{1F45F}'),
  back('BACK', '\u{1F9B8}'),
  neck('NECK', '\u{1F9E3}');

  final String _label;
  final String emoji;
  const HeroSlot(this._label, this.emoji);

  String get label => _label;
}

/// Draw order of the slots, bottom to top. Used when several worn items
/// share one layer (e.g. bottoms and shoes both paint on the legs).
const List<HeroSlot> kSlotDrawOrder = [
  HeroSlot.back,
  HeroSlot.bottom,
  HeroSlot.shoes,
  HeroSlot.top,
  HeroSlot.neck,
  HeroSlot.face,
  HeroSlot.head,
];

/// One wearable. Art for it lives in hero_item_art.dart (generated).
///
/// HOW IT IS GOT:
///  * price 0 + no rule           free starter item
///  * price 0 + rule              EARNED: unlocks by itself (level / km / rank / stars)
///  * coins price                 BOUGHT once (rule must also be met, if any)
class HeroItem {
  final String id;
  final HeroSlot slot;
  final String name;
  final String emoji;

  /// 0 common · 1 rare · 2 epic · 3 legendary (colours the shop card).
  final int rarity;

  final int coins;
  final UnlockRule rule;

  const HeroItem(
    this.id,
    this.slot,
    this.name,
    this.emoji, {
    this.rarity = 0,
    this.coins = 0,
    this.rule = UnlockRule.none,
  });

  /// Pixel-art icon of this item (assets/images/icons/items).
  String get iconPath => 'assets/images/icons/items/item_$id.png';

  bool get isFree => coins == 0 && rule.isNone;
  bool get isEarned => coins == 0 && !rule.isNone;
  bool get isForSale => coins > 0;

  /// "120 \u{1FA99}" / "FREE" / "EARN".
  String get priceLabel {
    if (coins > 0) return '$coins \u{1FA99}';
    return isFree ? 'FREE' : 'EARN';
  }
}

const List<HeroItem> kHeroItems = [
  // ── HEAD ──
  HeroItem('cap_red', HeroSlot.head, 'Red Cap', '\u{1F9E2}'),
  HeroItem('beanie_blue', HeroSlot.head, 'Blue Beanie', '\u{1F9F6}',
      rule: UnlockRule(level: 2)),
  HeroItem('ears_cat', HeroSlot.head, 'Cat Ears', '\u{1F431}',
      rarity: 1, coins: 120),
  HeroItem('wizard_hat', HeroSlot.head, 'Wizard Hat', '\u{1F9D9}',
      rarity: 1, rule: UnlockRule(level: 10)),
  HeroItem('helm_knight', HeroSlot.head, 'Knight Helm', '\u{1FA96}',
      rarity: 1, rule: UnlockRule(stageId: 'stage_novice')),
  HeroItem('halo', HeroSlot.head, 'Angel Halo', '\u{1F607}',
      rarity: 2, coins: 400),
  HeroItem('crown_gold', HeroSlot.head, 'Gold Crown', '\u{1F451}',
      rarity: 3, rule: UnlockRule(stageId: 'stage_slayer')),

  HeroItem('sweatband', HeroSlot.head, 'Sweatband', '\u{1F3BD}',
      coins: 60),
  HeroItem('bucket_hat', HeroSlot.head, 'Bucket Hat', '\u{1F452}',
      coins: 150),
  HeroItem('beret', HeroSlot.head, 'Painter Beret', '\u{1F3A8}',
      coins: 180),
  HeroItem('tophat', HeroSlot.head, 'Top Hat', '\u{1F3A9}',
      rarity: 1, coins: 350),
  HeroItem('viking', HeroSlot.head, 'Viking Helm', '\u{1FA96}',
      rarity: 1, coins: 500),
  HeroItem('pirate_hat', HeroSlot.head, 'Captain Hat', '\u{1F3F4}',
      rarity: 2, coins: 800),
  HeroItem('crown_ice', HeroSlot.head, 'Frost Crown', '\u2744\uFE0F',
      rarity: 2, coins: 1200),
  HeroItem('crown_royal', HeroSlot.head, 'Royal Crown', '\u{1F451}',
      rarity: 3, coins: 2800),

  // ── FACE ──
  HeroItem('stache', HeroSlot.face, 'Fancy Stache', '\u{1F468}',
      coins: 60),
  HeroItem('glasses_round', HeroSlot.face, 'Round Glasses', '\u{1F453}',
      coins: 80),
  HeroItem('shades', HeroSlot.face, 'Cool Shades', '\u{1F60E}',
      rarity: 1, coins: 150),
  HeroItem('mask_hero', HeroSlot.face, 'Hero Mask', '\u{1F9B9}',
      rarity: 1, rule: UnlockRule(level: 3)),

  HeroItem('freckles', HeroSlot.face, 'Freckles', '\u{1F33E}',
      coins: 50),
  HeroItem('blush', HeroSlot.face, 'Rosy Blush', '\u{1F60A}',
      coins: 60),
  HeroItem('bandage', HeroSlot.face, 'Bandage', '\u{1FA79}',
      coins: 70),
  HeroItem('glasses_nerd', HeroSlot.face, 'Nerd Glasses', '\u{1F913}',
      coins: 120),
  HeroItem('goggles_swim', HeroSlot.face, 'Swim Goggles', '\u{1F97D}',
      coins: 160),
  HeroItem('eyepatch', HeroSlot.face, 'Pirate Patch', '\u{1F3F4}\u200D\u2620\uFE0F',
      rarity: 1, coins: 280),
  HeroItem('beard', HeroSlot.face, 'Bushy Beard', '\u{1F9D4}',
      rarity: 1, coins: 350),
  HeroItem('visor_cyber', HeroSlot.face, 'Cyber Visor', '\u{1F576}\uFE0F',
      rarity: 1, coins: 500),
  HeroItem('shades_star', HeroSlot.face, 'Star Shades', '\u2B50',
      rarity: 2, coins: 700),
  HeroItem('mask_masq', HeroSlot.face, 'Masquerade Mask', '\u{1F3AD}',
      rarity: 2, coins: 1000),
  HeroItem('shades_diamond', HeroSlot.face, 'Diamond Shades', '\u{1F48E}',
      rarity: 3, coins: 2200),

  // ── TOP ──
  HeroItem('tee_stripes', HeroSlot.top, 'Striped Tee', '\u{1F455}',
      coins: 100),
  HeroItem('hoodie_orange', HeroSlot.top, 'Orange Hoodie', '\u{1F9E5}',
      rarity: 1, rule: UnlockRule(level: 6)),
  HeroItem('jersey_bolt', HeroSlot.top, 'Bolt Jersey', '⚡',
      rarity: 1, coins: 200),
  HeroItem('gi_ninja', HeroSlot.top, 'Ninja Gi', '\u{1F977}',
      rarity: 2, coins: 350),
  HeroItem('armor_silver', HeroSlot.top, 'Silver Armor', '\u{1F6E1}',
      rarity: 2, rule: UnlockRule(stageId: 'stage_vanguard')),
  HeroItem('armor_gold', HeroSlot.top, 'Golden Armor', '\u{1F3C6}',
      rarity: 3, rule: UnlockRule(stars: 9)),

  HeroItem('tee_lime', HeroSlot.top, 'Lime Tee', '\u{1F455}',
      coins: 80),
  HeroItem('polo_navy', HeroSlot.top, 'Navy Polo', '\u{1F454}',
      coins: 140),
  HeroItem('tank_sport', HeroSlot.top, 'Sport Tank', '\u{1F3C0}',
      coins: 180),
  HeroItem('flannel', HeroSlot.top, 'Flannel Shirt', '\u{1F332}',
      rarity: 1, coins: 300),
  HeroItem('varsity', HeroSlot.top, 'Varsity Jacket', '\u{1F3C8}',
      rarity: 1, coins: 450),
  HeroItem('track_retro', HeroSlot.top, 'Retro Track Jacket', '\u{1F3C3}',
      rarity: 1, coins: 500),
  HeroItem('robe_star', HeroSlot.top, 'Starry Robe', '\u{1F31F}',
      rarity: 2, coins: 900),
  HeroItem('armor_crystal', HeroSlot.top, 'Crystal Plate', '\u{1F48E}',
      rarity: 2, coins: 1200),
  HeroItem('armor_dragon', HeroSlot.top, 'Dragon Scale Armor', '\u{1F409}',
      rarity: 3, coins: 2500),

  // ── BOTTOM ──
  HeroItem('shorts_red', HeroSlot.bottom, 'Red Shorts', '\u{1FA73}'),
  HeroItem('pants_track', HeroSlot.bottom, 'Track Pants', '\u{1F456}',
      coins: 120),
  HeroItem('pants_camo', HeroSlot.bottom, 'Camo Pants', '\u{1F332}',
      rarity: 1, coins: 250),
  HeroItem('shorts_gold', HeroSlot.bottom, 'Gold Shorts', '\u{1F947}',
      rarity: 2, rule: UnlockRule(km: 25)),

  HeroItem('shorts_denim', HeroSlot.bottom, 'Denim Shorts', '\u{1FA73}',
      coins: 70),
  HeroItem('shorts_gym', HeroSlot.bottom, 'Gym Shorts', '\u{1F3CB}',
      coins: 90),
  HeroItem('jeans', HeroSlot.bottom, 'Blue Jeans', '\u{1F456}',
      coins: 150),
  HeroItem('pants_khaki', HeroSlot.bottom, 'Khaki Pants', '\u{1F9F3}',
      coins: 180),
  HeroItem('joggers', HeroSlot.bottom, 'Black Joggers', '\u{1F3C3}',
      rarity: 1, coins: 280),
  HeroItem('shorts_board', HeroSlot.bottom, 'Board Shorts', '\u{1F3C4}',
      rarity: 1, coins: 320),
  HeroItem('pants_plaid', HeroSlot.bottom, 'Plaid Pants', '\u{1F3B8}',
      rarity: 1, coins: 450),
  HeroItem('hakama', HeroSlot.bottom, 'Shadow Hakama', '\u{1F977}',
      rarity: 2, coins: 750),
  HeroItem('leggings_galaxy', HeroSlot.bottom, 'Galaxy Leggings', '\u{1F30C}',
      rarity: 2, coins: 1100),
  HeroItem('greaves', HeroSlot.bottom, 'Knight Greaves', '\u{1F6E1}\uFE0F',
      rarity: 2, coins: 1300),
  HeroItem('pants_royal', HeroSlot.bottom, 'Royal Trousers', '\u{1F451}',
      rarity: 3, coins: 2200),

  // ── SHOES ──
  HeroItem('sneak_red', HeroSlot.shoes, 'Red Sneakers', '\u{1F45F}'),
  HeroItem('runners_neon', HeroSlot.shoes, 'Neon Runners', '\u{1F3C3}',
      rarity: 1, rule: UnlockRule(level: 8)),
  HeroItem('boots_gold', HeroSlot.shoes, 'Gold Boots', '\u{1F97E}',
      rarity: 2, coins: 450),
  HeroItem('wing_shoes', HeroSlot.shoes, 'Winged Sneakers', '\u{1FABD}',
      rarity: 2, coins: 600),
  HeroItem('rocket_boots', HeroSlot.shoes, 'Rocket Boots', '\u{1F680}',
      rarity: 3, rule: UnlockRule(km: 100)),

  HeroItem('slides', HeroSlot.shoes, 'Comfy Slides', '\u{1FA74}',
      coins: 60),
  HeroItem('sneak_blue', HeroSlot.shoes, 'Blue Kicks', '\u{1F45F}',
      coins: 70),
  HeroItem('sneak_white', HeroSlot.shoes, 'Clean Whites', '\u{1F45F}',
      coins: 100),
  HeroItem('hightops', HeroSlot.shoes, 'Hi-Tops', '\u{1F45F}',
      coins: 180),
  HeroItem('boots_hiking', HeroSlot.shoes, 'Hiking Boots', '\u{1F97E}',
      rarity: 1, coins: 300),
  HeroItem('cleats', HeroSlot.shoes, 'Pro Cleats', '\u26BD',
      rarity: 1, coins: 400),
  HeroItem('sneak_flame', HeroSlot.shoes, 'Flame Kicks', '\u{1F525}',
      rarity: 1, coins: 550),
  HeroItem('boots_frost', HeroSlot.shoes, 'Frost Boots', '\u2744\uFE0F',
      rarity: 2, coins: 900),
  HeroItem('sneak_galaxy', HeroSlot.shoes, 'Galaxy Runners', '\u{1F30C}',
      rarity: 2, coins: 1200),
  HeroItem('boots_dragon', HeroSlot.shoes, 'Dragon Boots', '\u{1F409}',
      rarity: 3, coins: 2400),

  // ── BACK ──
  HeroItem('cape_red', HeroSlot.back, 'Hero Cape', '\u{1F9B8}',
      rarity: 1, rule: UnlockRule(level: 5)),
  HeroItem('backpack', HeroSlot.back, 'Hiker Backpack', '\u{1F392}',
      coins: 130),
  HeroItem('wings_bat', HeroSlot.back, 'Bat Wings', '\u{1F987}',
      rarity: 2, rule: UnlockRule(stars: 5)),
  HeroItem('wings_angel', HeroSlot.back, 'Angel Wings', '\u{1FABD}',
      rarity: 3, coins: 800),

  HeroItem('sling_bag', HeroSlot.back, 'Sling Bag', '\u{1F45C}',
      coins: 90),
  HeroItem('backpack_school', HeroSlot.back, 'School Pack', '\u{1F392}',
      coins: 150),
  HeroItem('quiver', HeroSlot.back, 'Archer Quiver', '\u{1F3F9}',
      coins: 200),
  HeroItem('cape_night', HeroSlot.back, 'Night Cape', '\u{1F319}',
      rarity: 1, coins: 300),
  HeroItem('surfboard', HeroSlot.back, 'Surfboard', '\u{1F3C4}',
      rarity: 1, coins: 380),
  HeroItem('wings_butterfly', HeroSlot.back, 'Butterfly Wings', '\u{1F98B}',
      rarity: 1, coins: 550),
  HeroItem('shield_round', HeroSlot.back, 'Knight Shield', '\u{1F6E1}\uFE0F',
      rarity: 2, coins: 750),
  HeroItem('wings_fairy', HeroSlot.back, 'Fairy Wings', '\u{1F9DA}',
      rarity: 2, coins: 900),
  HeroItem('jetpack', HeroSlot.back, 'Jetpack', '\u{1F680}',
      rarity: 2, coins: 1100),
  HeroItem('cape_royal', HeroSlot.back, 'Royal Cape', '\u{1F451}',
      rarity: 3, coins: 2000),

  // ── NECK ──
  HeroItem('scarf_red', HeroSlot.neck, 'Red Scarf', '\u{1F9E3}',
      rule: UnlockRule(level: 4)),
  HeroItem('medal_gold', HeroSlot.neck, 'Gold Medal', '\u{1F3C5}',
      rarity: 1, rule: UnlockRule(km: 10)),
  HeroItem('belt_champ', HeroSlot.neck, 'Champion Belt', '\u{1F94A}',
      rarity: 2, rule: UnlockRule(km: 50)),
  HeroItem('tie_red', HeroSlot.neck, 'Red Tie', '\u{1F454}',
      coins: 60),
  HeroItem('bowtie', HeroSlot.neck, 'Bow Tie', '\u{1F380}',
      coins: 80),
  HeroItem('bandana', HeroSlot.neck, 'Neck Bandana', '\u{1F9E3}',
      coins: 100),
  HeroItem('whistle', HeroSlot.neck, 'Coach Whistle', '\u{1F4E3}',
      coins: 120),
  HeroItem('scarf_cozy', HeroSlot.neck, 'Cozy Scarf', '\u{1F9E3}',
      coins: 150),
  HeroItem('dogtags', HeroSlot.neck, 'Dog Tags', '\u{1F3F7}\uFE0F',
      rarity: 1, coins: 250),
  HeroItem('neckphones', HeroSlot.neck, 'Neck Phones', '\u{1F3A7}',
      rarity: 1, coins: 380),
  HeroItem('pearls', HeroSlot.neck, 'Pearl Necklace', '\u{1F9AA}',
      rarity: 1, coins: 450),
  HeroItem('chain_gold', HeroSlot.neck, 'Gold Chain', '\u26D3\uFE0F',
      rarity: 2, coins: 700),
  HeroItem('amulet', HeroSlot.neck, 'Mystic Amulet', '\u{1F52E}',
      rarity: 2, coins: 1000),
  HeroItem('medallion', HeroSlot.neck, 'Hero Medallion', '\u{1F3C5}',
      rarity: 2, coins: 1300),
  HeroItem('collar_diamond', HeroSlot.neck, 'Diamond Collar', '\u{1F48D}',
      rarity: 3, coins: 2500),
];

HeroItem? heroItemById(Object? id) {
  if (id is! String) return null;
  for (final i in kHeroItems) {
    if (i.id == id) return i;
  }
  return null;
}

List<HeroItem> heroItemsIn(HeroSlot slot) =>
    [for (final i in kHeroItems) if (i.slot == slot) i];

/// Is [i] wearable now? Free: yes. Priced: only once bought (and rule met).
/// Earned: when its rule is met.
bool isItemUnlocked(HeroItem i, HeroProgress p) {
  if (i.isFree) return true;
  if (!i.rule.isNone && !i.rule.met(p)) return false;
  if (i.isForSale) return p.ownedItems.contains(i.id);
  return true;
}

/// What the lock says: the rule, or the price when it is for sale.
String? itemLockHint(HeroItem i, HeroProgress p) {
  if (isItemUnlocked(i, p)) return null;
  if (!i.rule.isNone && !i.rule.met(p)) return i.rule.label;
  return i.priceLabel;
}

/// slot name -> item id, as saved in users/{uid}.hero_outfit.
typedef HeroOutfit = Map<String, String>;

/// Read the saved outfit, dropping unknown ids.
HeroOutfit outfitOf(Map<String, dynamic>? data) {
  final raw = data?['hero_outfit'];
  final out = <String, String>{};
  if (raw is Map) {
    for (final s in HeroSlot.values) {
      final item = heroItemById(raw[s.name]);
      if (item != null && item.slot == s) out[s.name] = item.id;
    }
  }
  return out;
}

/// SVG layers (full 286x512 canvas) of the worn items for one body layer,
/// bottom to top. [layer]: back | head | body | arm_back | arm_front |
/// leg_back | leg_front.
List<String> outfitSvgs(HeroOutfit outfit, BodyTier tier, String layer) {
  if (outfit.isEmpty) return const <String>[];
  final out = <String>[];
  for (final slot in kSlotDrawOrder) {
    final id = outfit[slot.name];
    if (id == null) continue;
    final svg = kHeroItemArt['$id/${tier.id}/$layer'];
    if (svg != null) out.add(svg);
  }
  return out;
}
