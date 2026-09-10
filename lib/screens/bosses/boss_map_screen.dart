import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/boss_definitions.dart';
import '../../utils/combat_power.dart';
import '../../theme/app_colors.dart';

class BossMapScreen extends StatefulWidget {
  const BossMapScreen({super.key});

  @override
  State<BossMapScreen> createState() => _BossMapScreenState();
}

class _BossMapScreenState extends State<BossMapScreen> {
  Set<String> _defeatedIds = {};
  int _playerLevel = 1;
  bool _loading = true;
  bool _fighting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data() ?? {};
      if (mounted) {
        setState(() {
          _defeatedIds = Set<String>.from(
              (data['defeated_boss_ids'] as List<dynamic>? ?? []).map((e) => e.toString()));
          _playerLevel = (data['level'] as num?)?.toInt() ?? 1;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isUnlocked(int index) {
    if (index == 0) return true;
    return _defeatedIds.contains(kBossList[index - 1].id);
  }

  void _onTapBoss(int index) {
    if (_fighting) return;
    if (!_isUnlocked(index)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Defeat ${kBossList[index - 1].name} first!')),
      );
      return;
    }
    _showBossSheet(kBossList[index]);
  }

  void _showBossSheet(BossDefinition boss) {
    final defeated = _defeatedIds.contains(boss.id);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _BossDetailSheet(
        boss: boss,
        alreadyDefeated: defeated,
        playerLevel: _playerLevel,
        onFight: () => _resolveFight(boss),
      ),
    );
  }

  // NOTE: Combat Power here uses level only. Your equipped gear stats
  // currently live only in local Equipment screen state, not Firestore,
  // so they can't factor in here yet — see combat_power.dart notes.
  Future<void> _resolveFight(BossDefinition boss) async {
    Navigator.of(context).pop(); // close the detail sheet
    setState(() => _fighting = true);

    final playerCp = CombatPower.calculate(level: _playerLevel);
    final chance = CombatPower.winChance(playerCp, boss.power);
    final roll = Random().nextDouble();
    final won = roll <= chance;

    await Future.delayed(const Duration(milliseconds: 900)); // brief "battle" beat

    BossLoot? loot;
    if (won) {
      loot = _rollLoot(boss.lootTable);
      await _saveVictory(boss, loot);
    }

    if (!mounted) return;
    setState(() => _fighting = false);
    _showResultSheet(boss: boss, won: won, loot: loot, playerCp: playerCp, chance: chance);
  }

  BossLoot _rollLoot(List<BossLoot> table) {
    final totalWeight = table.fold<int>(0, (sum, l) => sum + l.weight);
    int roll = Random().nextInt(totalWeight);
    for (final loot in table) {
      if (roll < loot.weight) return loot;
      roll -= loot.weight;
    }
    return table.first;
  }

  Future<void> _saveVictory(BossDefinition boss, BossLoot loot) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    await userRef.update({
      'defeated_boss_ids': FieldValue.arrayUnion([boss.id]),
      'inventory': FieldValue.arrayUnion([
        {
          'name': loot.name,
          'rarity': loot.rarity,
          'icon': loot.icon,
          'slot': loot.slot,
          'source': 'boss:${boss.id}',
          'obtained_at': DateTime.now().toIso8601String(),
        }
      ]),
    });

    if (mounted) {
      setState(() => _defeatedIds = {..._defeatedIds, boss.id});
    }
  }

  void _showResultSheet({
    required BossDefinition boss,
    required bool won,
    BossLoot? loot,
    required int playerCp,
    required double chance,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: !won, // force acknowledging a win's loot
      builder: (_) => _BattleResultSheet(
        boss: boss,
        won: won,
        loot: loot,
        playerCp: playerCp,
        chancePercent: (chance * 100).round(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgPanel,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.blue),
        title: const Text(
          'BOSS MAP',
          style: TextStyle(
            color: AppColors.blue,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
            fontSize: 15,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
          : SafeArea(
              child: ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: kBossList.length,
                itemBuilder: (context, index) {
                  final boss = kBossList[index];
                  final unlocked = _isUnlocked(index);
                  final defeated = _defeatedIds.contains(boss.id);
                  return Column(
                    children: [
                      _BossNode(
                        boss: boss,
                        unlocked: unlocked,
                        defeated: defeated,
                        onTap: () => _onTapBoss(index),
                      ),
                      if (index < kBossList.length - 1)
                        Container(
                          width: 3,
                          height: 36,
                          color: unlocked ? AppColors.blue.withOpacity(0.4) : AppColors.borderDim,
                        ),
                    ],
                  );
                },
              ),
            ),
    );
  }
}

class _BossNode extends StatelessWidget {
  final BossDefinition boss;
  final bool unlocked;
  final bool defeated;
  final VoidCallback onTap;

  const _BossNode({
    required this.boss,
    required this.unlocked,
    required this.defeated,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = defeated
        ? AppColors.gold
        : unlocked
            ? AppColors.blue
            : AppColors.borderDim;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.6), width: defeated ? 2 : 1),
          boxShadow: unlocked
              ? [BoxShadow(color: color.withOpacity(0.15), blurRadius: 12)]
              : [],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.12),
                border: Border.all(color: color.withOpacity(0.6), width: 2),
              ),
              child: Center(
                child: unlocked
                    ? Text(boss.emoji, style: const TextStyle(fontSize: 26))
                    : const Icon(Icons.lock, color: AppColors.textSub, size: 22),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unlocked ? boss.name : '???',
                    style: TextStyle(
                      color: unlocked ? AppColors.textMain : AppColors.textSub,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    unlocked ? 'Power: ${boss.power}' : 'Defeat previous boss to unlock',
                    style: const TextStyle(color: AppColors.textSub, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (defeated)
              const Icon(Icons.check_circle, color: AppColors.gold, size: 22),
          ],
        ),
      ),
    );
  }
}

class _BossDetailSheet extends StatelessWidget {
  final BossDefinition boss;
  final bool alreadyDefeated;
  final int playerLevel;
  final VoidCallback onFight;

  const _BossDetailSheet({
    required this.boss,
    required this.alreadyDefeated,
    required this.playerLevel,
    required this.onFight,
  });

  @override
  Widget build(BuildContext context) {
    final playerCp = CombatPower.calculate(level: playerLevel);
    final chance = (CombatPower.winChance(playerCp, boss.power) * 100).round();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.bgPanel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: AppColors.borderDim, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Text(boss.emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 8),
          Text(
            boss.name,
            style: const TextStyle(color: AppColors.blue, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          Text(
            boss.flavorText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSub, fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (alreadyDefeated)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('DEFEATED — fight again for another loot chance',
                  style: TextStyle(color: AppColors.gold, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Your CP: $playerCp', style: const TextStyle(color: AppColors.textMain, fontSize: 12)),
              const SizedBox(width: 16),
              Text('Boss Power: ${boss.power}', style: const TextStyle(color: AppColors.textMain, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Estimated win chance: $chance%',
              style: const TextStyle(color: AppColors.cyan, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onFight,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('FIGHT',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 3)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BattleResultSheet extends StatelessWidget {
  final BossDefinition boss;
  final bool won;
  final BossLoot? loot;
  final int playerCp;
  final int chancePercent;

  const _BattleResultSheet({
    required this.boss,
    required this.won,
    this.loot,
    required this.playerCp,
    required this.chancePercent,
  });

  @override
  Widget build(BuildContext context) {
    final color = won ? AppColors.gold : AppColors.red;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.bgPanel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: color, width: 2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: AppColors.borderDim, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Icon(won ? Icons.emoji_events : Icons.close, color: color, size: 48),
          const SizedBox(height: 8),
          Text(
            won ? 'VICTORY!' : 'DEFEATED...',
            style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 3),
          ),
          const SizedBox(height: 6),
          Text(
            won ? 'You defeated ${boss.name}!' : '${boss.name} was too strong this time.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSub, fontSize: 13),
          ),
          if (won && loot != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (kRarityColorForBoss[loot!.rarity] ?? AppColors.textSub).withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: (kRarityColorForBoss[loot!.rarity] ?? AppColors.textSub).withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  Text(loot!.icon, style: const TextStyle(fontSize: 32)),
                  const SizedBox(height: 6),
                  Text(loot!.name,
                      style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.bold)),
                  Text(loot!.rarity,
                      style: TextStyle(color: kRarityColorForBoss[loot!.rarity], fontSize: 11)),
                ],
              ),
            ),
          ],
          if (!won) ...[
            const SizedBox(height: 12),
            Text('Level up or gear up, then try again.',
                style: const TextStyle(color: AppColors.textSub, fontSize: 11)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: won ? AppColors.gold : AppColors.borderDim,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(won ? 'CLAIM LOOT' : 'CLOSE',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }
}