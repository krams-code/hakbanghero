import 'package:flutter/material.dart';

import 'character_profile.dart' show BodyTier, BodyTierExt;
import 'hero_progress.dart';

/// A playable block hero. The art lives in
/// assets/images/heroes/<id>/<bodyTier>/<layer>.png (see hero_rig.dart).
///
/// ADD A HERO: draw the 7 pictures per body form (generator), add one
/// HeroDef below, and add its folders to pubspec.yaml. Nothing else.
///
/// The chosen hero is saved as `hero_id` on users/{uid}; bought heroes go in
/// `owned_heroes`.
class HeroDef {
  final String id;
  final String name;
  final String tagline;
  final Color color;
  final Color edge;

  /// Anyone may pick this one on day one (the first-launch choice).
  final bool starter;

  /// Coins to buy it (0 = not for sale, earned by [rule] instead).
  final int coinPrice;

  /// Level / km / rank / star requirement (all must be met). A hero with BOTH
  /// a price and a rule must meet the rule first, then be bought.
  final UnlockRule rule;

  /// Full-body costume hero (a single picture, no gear slots, no weight
  /// forms). The human hero SPROUT is the only one with the layered rig.
  final bool costume;

  /// 0 starter . 1 common . 2 rare . 3 epic . 4 legendary
  final int rarity;

  const HeroDef({
    required this.id,
    required this.name,
    required this.tagline,
    required this.color,
    required this.edge,
    this.starter = false,
    this.coinPrice = 0,
    this.rule = UnlockRule.none,
    this.costume = true,
    this.rarity = 1,
  });

  /// "Earned" heroes unlock by themselves when [rule] is met.
  bool get isEarned => coinPrice == 0 && !starter;

  String get rarityLabel =>
      const ['STARTER', 'COMMON', 'RARE', 'EPIC', 'LEGENDARY'][rarity.clamp(0, 4)];
}

const String kDefaultHeroId = 'sprout';

/// Girl SPROUT: same hero (same id, gear, saves), drawn with the art in
/// assets/images/heroes/sprout_girl/ when the player's gender is female.
const String kGirlSproutArt = 'sprout_girl';

/// The signed-in player's look, set by UserDoc from users/{uid}.gender.
/// Used when a widget is not told whose hero it is drawing.
class HeroLook {
  HeroLook._();
  static bool meGirl = false;
}

/// 'male' | 'female' | null (not picked yet) from a stored gender value.
/// Tolerant of case, spaces and older spellings ('Female', 'girl', 'F'...).
String? genderKey(Object? gender) {
  if (gender is! String) return null;
  switch (gender.trim().toLowerCase()) {
    case 'female':
    case 'girl':
    case 'woman':
    case 'f':
      return 'female';
    case 'male':
    case 'boy':
    case 'man':
    case 'm':
      return 'male';
  }
  return null;
}

/// Name shown for a hero: SPROUT is "SPROUT GIRL" for girl players.
String heroDisplayName(HeroDef h, {bool? girl}) =>
    h.id == kDefaultHeroId && (girl ?? HeroLook.meGirl) ? 'SPROUT GIRL' : h.name;

/// Art folder to draw [heroId] with. [girl] = that player's gender is
/// female (null = the signed-in player's).
String heroArtId(String heroId, {bool? girl}) =>
    heroId == kDefaultHeroId && (girl ?? HeroLook.meGirl) ? kGirlSproutArt : heroId;

// HOW HEROES ARE GOT (same ideas as Brawl Stars / Subway Surfers / Crossy Road:
// a few free starters, cheap things you can buy in the first days, goals that
// unlock by themselves, and one big trophy hero):
//
//   STARTER   free, pick one on day one (the rest of the starters stay free)
//   COMMON    buy with coins (30-50): about 1-2 days of daily quests
//   RARE      EARNED by playing: a level, some km or a cleared rank
//   EPIC      a small goal first, THEN buy (100-150 coins)
//   LEGENDARY the Slayer rank trophy
const List<HeroDef> kHeroes = [
  // ── STARTERS (free) ──
  HeroDef(
    id: 'sprout',
    name: 'SPROUT',
    tagline: 'Fresh legs, big heart',
    color: Color(0xFF00B06F),
    edge: Color(0xFF006B44),
    starter: true,
    costume: false, // the classic human hero: wears all the shop gear
    rarity: 0,
  ),
  HeroDef(
    id: 'frog',
    name: 'FROG',
    tagline: 'Hop, hop, run!',
    color: Color(0xFF4CAF50),
    edge: Color(0xFF1F6B2A),
    starter: true,
    rarity: 0,
  ),
  HeroDef(
    id: 'penguin',
    name: 'PENGUIN',
    tagline: 'Waddles fast, never tires',
    color: Color(0xFF2F4A8A),
    edge: Color(0xFF14224A),
    starter: true,
    rarity: 0,
  ),
  HeroDef(
    id: 'slime',
    name: 'SLIME',
    tagline: 'Squishy and bouncy',
    color: Color(0xFF2FBF71),
    edge: Color(0xFF0F6B3E),
    starter: true,
    rarity: 0,
  ),

  // ── COMMON (buy with coins) ──
  HeroDef(
    id: 'bear',
    name: 'BEAR',
    tagline: 'Big hugs, big strides',
    color: Color(0xFF9C6B40),
    edge: Color(0xFF4A2F18),
    coinPrice: 300,
  ),
  HeroDef(
    id: 'cat',
    name: 'CAT',
    tagline: 'Lands on its feet',
    color: Color(0xFF7D8590),
    edge: Color(0xFF3A3F47),
    coinPrice: 300,
  ),
  HeroDef(
    id: 'fox',
    name: 'FOX',
    tagline: 'Quick and clever',
    color: Color(0xFFE8821E),
    edge: Color(0xFF7A3F0A),
    coinPrice: 400,
  ),
  HeroDef(
    id: 'panda',
    name: 'PANDA',
    tagline: 'Chill, then unstoppable',
    color: Color(0xFF5A6068),
    edge: Color(0xFF23262A),
    coinPrice: 400,
  ),
  HeroDef(
    id: 'dino',
    name: 'DINO',
    tagline: 'Rawr! Fresh from the park',
    color: Color(0xFF3FA84A),
    edge: Color(0xFF1B5A22),
    coinPrice: 500,
  ),

  // ── RARE (earned by playing) ──
  HeroDef(
    id: 'ghost',
    name: 'GHOST',
    tagline: 'Boo! Too fast to catch',
    color: Color(0xFF8E7CC3),
    edge: Color(0xFF433A66),
    rule: UnlockRule(level: 3),
    rarity: 2,
  ),
  HeroDef(
    id: 'shroom',
    name: 'SHROOM',
    tagline: 'Pops up on every trail',
    color: Color(0xFFD64545),
    edge: Color(0xFF7A1C20),
    rule: UnlockRule(km: 10),
    rarity: 2,
  ),
  HeroDef(
    id: 'pirate',
    name: 'PIRATE',
    tagline: 'Chasing treasure, one km at a time',
    color: Color(0xFF3B5FA8),
    edge: Color(0xFF172A55),
    rule: UnlockRule(level: 5),
    rarity: 2,
  ),
  HeroDef(
    id: 'ninja',
    name: 'NINJA',
    tagline: 'Silent and swift',
    color: Color(0xFF3A3A44),
    edge: Color(0xFF0E0E12),
    rule: UnlockRule(stageId: 'stage_novice'),
    rarity: 2,
  ),
  HeroDef(
    id: 'knight',
    name: 'KNIGHT',
    tagline: 'Armoured and unstoppable',
    color: Color(0xFF6F7C8E),
    edge: Color(0xFF2C3440),
    rule: UnlockRule(stageId: 'stage_vanguard'),
    rarity: 2,
  ),
  HeroDef(
    id: 'astronaut',
    name: 'ASTRONAUT',
    tagline: 'One small step... 50 km',
    color: Color(0xFF4C7BC4),
    edge: Color(0xFF1B3566),
    rule: UnlockRule(km: 50),
    rarity: 2,
  ),

  // ── EPIC (reach a goal, then buy) ──
  HeroDef(
    id: 'wizard',
    name: 'WIZARD',
    tagline: 'Pace by magic',
    color: Color(0xFF6A4FC4),
    edge: Color(0xFF2E1F6B),
    coinPrice: 1000,
    rule: UnlockRule(level: 6),
    rarity: 3,
  ),
  HeroDef(
    id: 'mech',
    name: 'MECH',
    tagline: 'Zero fatigue. Beep boop.',
    color: Color(0xFF4A6FA5),
    edge: Color(0xFF1A2E52),
    coinPrice: 1200,
    rule: UnlockRule(level: 8),
    rarity: 3,
  ),
  HeroDef(
    id: 'dragon',
    name: 'DRAGON',
    tagline: 'Breathes fire on the last km',
    color: Color(0xFF8A4FE0),
    edge: Color(0xFF3F1C7A),
    coinPrice: 1500,
    rule: UnlockRule(stars: 5),
    rarity: 3,
  ),

  // ── LEGENDARY (rank trophies) ──
  HeroDef(
    id: 'alien',
    name: 'ALIEN',
    tagline: 'Out of this world',
    color: Color(0xFF3FBF8A),
    edge: Color(0xFF14603F),
    rule: UnlockRule(stars: 9),
    rarity: 4,
  ),
  HeroDef(
    id: 'flame',
    name: 'FLAME',
    tagline: 'Born in the Abyss Citadel',
    color: Color(0xFFF07A1A),
    edge: Color(0xFF8A3A00),
    rule: UnlockRule(stageId: 'stage_slayer'),
    rarity: 4,
  ),
];

/// The hero with this id, or null.
HeroDef? heroById(Object? id) {
  if (id is! String) return null;
  for (final h in kHeroes) {
    if (h.id == id) return h;
  }
  return null;
}

/// Hero id stored on a users/{uid} map. Falls back to the default hero for
/// accounts that have not chosen yet, so the classic avatar is never shown.
/// (Declared nullable only so older call sites keep compiling; never null.)
String? heroIdOf(Map<String, dynamic>? data) =>
    heroById(data?['hero_id'])?.id ?? kDefaultHeroId;

/// True once the player has made their hero choice (first launch).
bool hasChosenHero(Map<String, dynamic>? data) =>
    heroById(data?['hero_id']) != null;

/// Can [h] be used right now?
///  * starters: always
///  * priced heroes: only once bought
///  * earned heroes: automatically when the rule is met
bool isHeroUnlocked(HeroDef h, HeroProgress p) {
  if (h.starter) return true;
  if (p.ownedHeroes.contains(h.id)) return true;
  if (h.coinPrice > 0) return false;
  return h.rule.met(p);
}

/// Why [h] is locked ("Reach LV 5", "120 🪙"), null when open.
String? heroLockHint(HeroDef h, HeroProgress p) {
  if (isHeroUnlocked(h, p)) return null;
  // priced hero with a goal: the goal comes first, then the purchase
  if (h.coinPrice > 0 && !h.rule.isNone && !h.rule.met(p)) {
    return h.rule.label ?? 'Locked';
  }
  if (h.coinPrice > 0) return 'Buy for ${h.coinPrice} \u{1FA99}';
  return h.rule.label ?? 'Locked';
}

/// A priced hero is only for sale once its goal (if any) is met.
bool heroCanBuy(HeroDef h, HeroProgress p) =>
    h.coinPrice > 0 && !p.ownedHeroes.contains(h.id) && h.rule.met(p);

/// Costume heroes have one picture; the human hero has a layered rig.
bool heroIsCostume(String heroId) => heroById(heroId)?.costume ?? false;

/// assets/images/heroes/ember/overweight/arm_front.png
String heroLayerAsset(String heroId, BodyTier tier, String layer) =>
    heroIsCostume(heroId)
        ? 'assets/images/heroes/$heroId/full.png'
        : 'assets/images/heroes/$heroId/${tier.id}/$layer.png';

/// Body form label ("Obese") for previews.
String heroTierLabel(BodyTier t) => t.label;
