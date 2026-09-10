import 'package:flutter/material.dart';

class BossLoot {
  final String name;
  final String rarity;
  final String icon;
  final String slot;
  final int weight; // relative drop weight within this boss's table

  const BossLoot({
    required this.name,
    required this.rarity,
    required this.icon,
    required this.slot,
    required this.weight,
  });
}

class BossDefinition {
  final String id;
  final String name;
  final String emoji;
  final int power;           // used against player's CP for win chance
  final String flavorText;
  final List<BossLoot> lootTable;

  const BossDefinition({
    required this.id,
    required this.name,
    required this.emoji,
    required this.power,
    required this.flavorText,
    required this.lootTable,
  });
}

/// Ordered boss list — each boss unlocks only after the previous one
/// is defeated. bossIndex 0 is always unlocked by default.
final List<BossDefinition> kBossList = [
  const BossDefinition(
    id: 'boss_slime_king',
    name: 'Slime King',
    emoji: '🟢',
    power: 1400,
    flavorText: 'A gelatinous ruler of the training grounds. Easy warm-up fight.',
    lootTable: [
      BossLoot(name: 'Iron Sword', rarity: 'Common', icon: '🗡️', slot: 'weapon', weight: 50),
      BossLoot(name: 'Leather Hood', rarity: 'Common', icon: '🪖', slot: 'helm', weight: 40),
      BossLoot(name: 'Storm Boots', rarity: 'Uncommon', icon: '👟', slot: 'boots', weight: 10),
    ],
  ),
  const BossDefinition(
    id: 'boss_marsh_wraith',
    name: 'Marsh Wraith',
    emoji: '👻',
    power: 1900,
    flavorText: 'Haunts the misty marshes. Drains stamina from unprepared heroes.',
    lootTable: [
      BossLoot(name: 'Shadow Cloak', rarity: 'Uncommon', icon: '🧥', slot: 'chest', weight: 45),
      BossLoot(name: 'Arcane Ring', rarity: 'Rare', icon: '💍', slot: 'ring', weight: 15),
      BossLoot(name: 'Storm Boots', rarity: 'Uncommon', icon: '👟', slot: 'boots', weight: 40),
    ],
  ),
  const BossDefinition(
    id: 'boss_highland_golem',
    name: 'Highland Golem',
    emoji: '🗿',
    power: 2500,
    flavorText: 'A towering stone guardian of the haunted highlands.',
    lootTable: [
      BossLoot(name: 'Forest Plate', rarity: 'Rare', icon: '🛡️', slot: 'chest', weight: 40),
      BossLoot(name: 'Phantom Blade', rarity: 'Epic', icon: '⚔️', slot: 'weapon', weight: 10),
      BossLoot(name: 'Arcane Ring', rarity: 'Rare', icon: '💍', slot: 'ring', weight: 50),
    ],
  ),
  const BossDefinition(
    id: 'boss_ashen_drake',
    name: 'Ashen Drake',
    emoji: '🐉',
    power: 3200,
    flavorText: 'A young dragon nesting in the ashen peaks. Not to be underestimated.',
    lootTable: [
      BossLoot(name: 'Phantom Blade', rarity: 'Epic', icon: '⚔️', slot: 'weapon', weight: 45),
      BossLoot(name: 'Shadow Crown', rarity: 'Epic', icon: '👑', slot: 'helm', weight: 45),
      BossLoot(name: 'Verdant Blade', rarity: 'Legendary', icon: '🌿', slot: 'weapon', weight: 10),
    ],
  ),
  const BossDefinition(
    id: 'boss_crystal_sentinel',
    name: 'Crystal Sentinel',
    emoji: '💎',
    power: 4000,
    flavorText: 'An ancient guardian fused with pure mana crystal.',
    lootTable: [
      BossLoot(name: 'Windrunner Treads', rarity: 'Epic', icon: '👟', slot: 'boots', weight: 50),
      BossLoot(name: 'Verdant Blade', rarity: 'Legendary', icon: '🌿', slot: 'weapon', weight: 30),
      BossLoot(name: 'Divine Gauntlet', rarity: 'Divine', icon: '🧤', slot: 'gloves', weight: 5),
    ],
  ),
  const BossDefinition(
    id: 'boss_shadow_fortress_lord',
    name: 'Shadow Fortress Lord',
    emoji: '👹',
    power: 5200,
    flavorText: 'The final trial. Only true heroes return from this fight.',
    lootTable: [
      BossLoot(name: 'Divine Gauntlet', rarity: 'Divine', icon: '🧤', slot: 'gloves', weight: 30),
      BossLoot(name: 'Verdant Blade', rarity: 'Legendary', icon: '🌿', slot: 'weapon', weight: 40),
      BossLoot(name: 'Shadow Crown', rarity: 'Epic', icon: '👑', slot: 'helm', weight: 30),
    ],
  ),
];

const Map<String, Color> kRarityColorForBoss = {
  'Common': Color(0xFF8A8AA8),
  'Uncommon': Color(0xFF2ECC71),
  'Rare': Color(0xFF2F9BFF),
  'Epic': Color(0xFF9B59FF),
  'Legendary': Color(0xFFFFD24C),
  'Divine': Color(0xFFFF6B6B),
};