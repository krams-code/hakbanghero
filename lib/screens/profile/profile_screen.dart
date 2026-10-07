import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:hakbanghero/models/activity_model.dart';

import '../../state/evolution_state.dart';
import '../../utils/player_stats.dart';
import '../../utils/xp_milestones.dart';
import '../../widgets/avatar_layer_stack.dart' show kSpriteWidth, kSpriteHeight;
import '../../widgets/avatar_preview.dart';
import '../../widgets/block_inputs.dart' show blockSnack;
import '../../widgets/block_ui.dart';
import '../../widgets/evolution_checkin_dialog.dart';
import '../../widgets/global_top_bar.dart' show confirmLogout;
import '../character/character_creation_screen.dart';

/// Player profile + fitness stat dashboard (Roblox block style).
///
/// No combat placeholders (ATK / DEF / HP). The three stat modules are
/// computed from real session history — see utils/player_stats.dart.
class ProfileScreen extends StatefulWidget {
  final VoidCallback? onBackTap;
  const ProfileScreen({super.key, this.onBackTap});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic> _user = {};
  FitnessStats? _fit;
  bool _loading = true;
  int _tab = 0; // 0 = STATS, 1 = RECORDS

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
      final db = FirebaseFirestore.instance;
      final userSnap = await db.collection('users').doc(uid).get();
      final actSnap = await db
          .collection('users')
          .doc(uid)
          .collection('activities')
          .orderBy('startTime', descending: true)
          .limit(120)
          .get();

      final sessions = <ActivitySession>[];
      for (final d in actSnap.docs) {
        try {
          sessions.add(ActivitySession.fromFirestore(d));
        } catch (_) {}
      }
      final data = userSnap.data() ?? <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _user = data;
        _fit = FitnessStats.compute(
          sessions,
          weightKg: (data['weight_kg'] as num?)?.toDouble(),
          enduranceBonus: (data['endurance_bonus'] as num?)?.toInt() ?? 0,
        );
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Weekly / monthly weight check-in. The avatar swap itself is global and
  /// instant (EvolutionState); here we only refresh stats and say what happened.
  Future<void> _checkIn() async {
    final r = await showEvolutionCheckIn(context);
    if (!mounted || r == null) return;
    _load();
    blockSnack(
      context,
      r.improved
          ? '🔥 EVOLVED INTO ${r.after.label.toUpperCase()}!'
              '${r.enduranceAwarded ? '  +${EvolutionState.enduranceBonus} ENDURANCE' : ''}'
          : '💾 Check-in saved: ${r.after.label}',
    );
  }

  Future<void> _editHero() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CharacterCreationScreen(isEditMode: true)),
    );
    if (mounted) _load();
  }

  // ───────────────────────── build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Rb.bg,
        body: Center(child: CircularProgressIndicator(color: Rb.green)),
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    final name = (_user['username'] as String?) ?? user?.displayName ?? 'Hero';
    final xp = (_user['xp'] as num?)?.toInt() ?? 0;
    final lv = LevelProgress.fromXp(xp);
    final fit = _fit!;

    return Scaffold(
      backgroundColor: Rb.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: Rb.green,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
            children: [
              _header(),
              const SizedBox(height: 14),
              _heroCard(name, lv.level),
              const SizedBox(height: 14),
              _expRail(lv),
              const SizedBox(height: 14),
              _currencyRow(),
              const SizedBox(height: 14),
              _tabs(),
              const SizedBox(height: 14),
              if (_tab == 0) ..._statsTab(fit) else ..._recordsTab(fit),
              const SizedBox(height: 20),
              PressBlock(
                color: Rb.red,
                edge: Rb.redEdge,
                depth: 8,
                radius: 16,
                padding: const EdgeInsets.symmetric(vertical: 15),
                onTap: () => confirmLogout(context),
                child: const SizedBox(
                  width: double.infinity,
                  child: Center(child: BlockText('🚪 LOGOUT SESSION', size: 17, stroke: 4.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── header ───────────────────────────────────────────────────────────
  Widget _header() => Block(
        color: Rb.hud,
        edge: Rb.hudEdge,
        depth: 6,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            if (widget.onBackTap != null) ...[
              PressBlock(
                color: const Color(0xFFE2E2E2),
                edge: const Color(0xFF6B6B6B),
                depth: 4,
                radius: 12,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                onTap: widget.onBackTap,
                child: const Text('◀',
                    style: TextStyle(
                        color: Color(0xFF232527),
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
            ],
            const Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: BlockText('👤 PLAYER PROFILE', size: 20, stroke: 4.5),
              ),
            ),
          ],
        ),
      );

  // ── character card: sky-blue rounded square ──────────────────────────
  Widget _heroCard(String name, int level) {
    return Block(
      color: const Color(0xFF8FD0FF),
      edge: Rb.blueEdge,
      depth: 8,
      radius: 24,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 330,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(21),
          child: GestureDetector(
            onTap: _editHero,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // pixel-sharp: ~0.5x of the 560px world
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 42),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    clipBehavior: Clip.none,
                    child: SizedBox(
                      width: kSpriteWidth,
                      height: kSpriteHeight + 44,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: 0,
                            top: 44,
                            width: kSpriteWidth,
                            height: kSpriteHeight,
                            child: AvatarPreview.fromData(
                              _user,
                              filterQuality: FilterQuality.none,
                              ownerUid: FirebaseAuth.instance.currentUser?.uid,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // grass baseplate
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Color(0xFF5BBF5B),
                      border: Border(top: BorderSide(color: Colors.black, width: 3)),
                    ),
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: BlockText(name.toUpperCase(), size: 16, stroke: 4),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: Block(
                    color: Rb.gold,
                    edge: Rb.goldEdge,
                    depth: 4,
                    radius: 10,
                    gloss: true,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: BlockText('⭐ LV $level', size: 13, stroke: 3.5),
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: PressBlock(
                    color: Rb.blue,
                    edge: Rb.blueEdge,
                    depth: 4,
                    radius: 10,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    onTap: _editHero,
                    child: const BlockText('✏️ EDIT HERO', size: 11, stroke: 3),
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 50,
                  child: PressBlock(
                    color: Rb.green,
                    edge: Rb.greenEdge,
                    depth: 4,
                    radius: 10,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    onTap: _checkIn,
                    child: BlockText(
                      EvolutionState.isCheckInDue(_user)
                          ? '⚖️ CHECK-IN ●'
                          : '⚖️ CHECK-IN',
                      size: 11,
                      stroke: 3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── EXP rail ─────────────────────────────────────────────────────────
  Widget _expRail(LevelProgress lv) {
    return Block(
      color: Rb.panel,
      edge: Rb.panelEdge,
      depth: 6,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BlockText('LV ${lv.level}', size: 16, stroke: 4, color: Rb.gold),
              const Spacer(),
              BlockText('EXP  ${_fmt(lv.xpIntoLevel)} / ${_fmt(lv.xpNeeded)}',
                  size: 13, stroke: 3.5),
            ],
          ),
          const SizedBox(height: 10),
          _RetroBar(fraction: lv.fraction),
          const SizedBox(height: 8),
          BlockText(
            '${_fmt(lv.xpNeeded - lv.xpIntoLevel)} XP TO LEVEL ${lv.level + 1}',
            size: 10,
            stroke: 2.5,
            color: const Color(0xFFB8BDC4),
          ),
          const SizedBox(height: 4),
          BlockText(
            nextXpMilestone((_user['xp'] as num?)?.toInt() ?? 0).text,
            size: 10,
            stroke: 2.5,
            color: Rb.gold,
          ),
        ],
      ),
    );
  }

  // ── currency ─────────────────────────────────────────────────────────
  Widget _currencyRow() {
    // Single currency: Mana Crystals fills the whole slot.
    return Block(
      color: const Color(0xFF2EC4FF),
      edge: const Color(0xFF0A6C99),
      depth: 5,
      radius: 12,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('💎', style: TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: BlockText(_fmt((_user['gems'] as num?)?.toInt() ?? 0),
                size: 22, stroke: 4.5),
          ),
          const SizedBox(width: 10),
          const BlockText('MANA CRYSTALS', size: 11, stroke: 3),
        ],
      ),
    );
  }

  // ── tabs ─────────────────────────────────────────────────────────────
  Widget _tabs() {
    Widget tab(int i, String label) {
      final sel = _tab == i;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: PressBlock(
            color: sel ? Rb.blue : Rb.panel,
            edge: sel ? Rb.blueEdge : Rb.panelEdge,
            depth: 5,
            radius: 12,
            forcePressed: sel,
            padding: const EdgeInsets.symmetric(vertical: 12),
            onTap: () => setState(() => _tab = i),
            child: Center(child: BlockText(label, size: 13, stroke: 3.5)),
          ),
        ),
      );
    }

    return Row(children: [tab(0, '📊 STATS'), tab(1, '🏆 RECORDS')]);
  }

  // ───────────────────────── STATS tab ─────────────────────────

  List<Widget> _statsTab(FitnessStats f) {
    final km = (_user['total_km'] as num?)?.toDouble() ?? 0;
    final sessions = (_user['total_sessions'] as num?)?.toInt() ?? 0;

    Widget summary(String emoji, String v, String label, Color c, Color e) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Block(
              color: c,
              edge: e,
              depth: 5,
              radius: 12,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Column(children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                FittedBox(
                    fit: BoxFit.scaleDown,
                    child: BlockText(v, size: 18, stroke: 4)),
                BlockText(label, size: 9, stroke: 2.5),
              ]),
            ),
          ),
        );

    return [
      Row(children: [
        summary('📍', km.toStringAsFixed(1), 'TOTAL KM', Rb.green, Rb.greenEdge),
        summary('🎯', '$sessions', 'SESSIONS', Rb.orange, Rb.orangeEdge),
        summary('⏱️', _duration(f.totalActiveSeconds), 'ACTIVE TIME', Rb.blue, Rb.blueEdge),
      ]),
      const SizedBox(height: 14),
      _module(
        emoji: '🏃‍♂️',
        title: 'PACE / AGILITY',
        rank: _agilityRank(f.avgSpeedKmh),
        big: f.avgSpeedKmh > 0 ? '${f.avgSpeedKmh.toStringAsFixed(1)} km/h' : '— km/h',
        bigLabel: 'AVG SPEED (LAST 10 SESSIONS)',
        fraction: f.agilityFraction,
        color: const Color(0xFF2EC4FF),
        edge: const Color(0xFF0A6C99),
        foot: f.bestSpeedKmh > 0
            ? '🏅 Best session: ${f.bestSpeedKmh.toStringAsFixed(1)} km/h  •  Goal 15 km/h'
            : 'Finish a session to set your speed record!',
      ),
      const SizedBox(height: 14),
      _module(
        emoji: '🔋',
        title: 'STAMINA POOL',
        rank: '${f.consistentWeeks} WK CONSISTENT',
        big: '${_fmt(f.weeklyKcal)} / ${_fmt(f.staminaMax)}',
        bigLabel: 'KCAL BURNED THIS WEEK (EST.)',
        fraction: f.staminaMax == 0 ? 0 : (f.weeklyKcal / f.staminaMax).clamp(0.0, 1.0),
        color: Rb.neon,
        edge: Rb.greenEdge,
        foot:
            '🔥 ${f.weeklyActiveDays}/7 active days  •  ${f.weeklyKm.toStringAsFixed(1)} km  •  Pool grows +250 per consistent week (2+ sessions)',
      ),
      const SizedBox(height: 14),
      _module(
        emoji: '🛡️',
        title: 'RECOVERY / ENDURANCE',
        rank: _enduranceRank(f.enduranceFraction),
        big: '${f.streakDays}-DAY STREAK',
        bigLabel: 'ACTIVE RUN STREAK',
        fraction: f.enduranceFraction,
        color: Rb.gold,
        edge: Rb.goldEdge,
        foot: '📅 ${f.sessions30d} sessions in the last 30 days  •  Keep the streak alive to level up!',
      ),
    ];
  }

  Widget _module({
    required String emoji,
    required String title,
    required String rank,
    required String big,
    required String bigLabel,
    required double fraction,
    required Color color,
    required Color edge,
    required String foot,
  }) {
    return Block(
      color: Rb.panel,
      edge: Rb.panelEdge,
      depth: 6,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Block(
                color: color,
                edge: edge,
                depth: 3,
                radius: 10,
                padding: EdgeInsets.zero,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: BlockText(title, size: 15, stroke: 4),
                ),
              ),
              const SizedBox(width: 8),
              Block(
                color: Rb.slot,
                edge: Rb.slateEdge,
                depth: 3,
                radius: 8,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: BlockText(rank, size: 9, stroke: 2.5, color: color),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: BlockText(big, size: 26, stroke: 5, color: color),
          ),
          BlockText(bigLabel, size: 9, stroke: 2.5, color: const Color(0xFFB8BDC4)),
          const SizedBox(height: 10),
          _RetroBar(fraction: fraction, color: color, height: 24),
          const SizedBox(height: 8),
          Text(
            foot,
            style: const TextStyle(
              color: Color(0xFFB8BDC4),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  String _agilityRank(double v) {
    if (v <= 0) return 'UNRANKED';
    if (v < 4) return 'ROOKIE';
    if (v < 7) return 'SCOUT';
    if (v < 10) return 'RANGER';
    if (v < 13) return 'SPRINTER';
    return 'ELITE';
  }

  String _enduranceRank(double f) {
    if (f <= 0) return 'RESTING';
    if (f < 0.25) return 'WARMING UP';
    if (f < 0.5) return 'STEADY';
    if (f < 0.8) return 'IRON LEGS';
    return 'UNSTOPPABLE';
  }

  // ───────────────────────── RECORDS tab ─────────────────────────

  List<Widget> _recordsTab(FitnessStats f) {
    String pace = '—';
    if (f.bestPaceSecsPerKm > 0) {
      final m = f.bestPaceSecsPerKm ~/ 60;
      final s = f.bestPaceSecsPerKm % 60;
      pace = "$m'${s.toString().padLeft(2, '0')}\" /km";
    }
    final km = (_user['total_km'] as num?)?.toDouble() ?? 0;
    final sessions = (_user['total_sessions'] as num?)?.toInt() ?? 0;
    final owned = _user['owned_items'];
    final bought = owned is List && owned.isNotEmpty;
    final bestStreak = f.longestStreakDays;

    final records = <(String, String, String, Color, Color)>[
      ('🏅', 'Longest Run', f.longestRunKm > 0 ? '${f.longestRunKm.toStringAsFixed(2)} km' : '—',
          Rb.green, Rb.greenEdge),
      ('⚡', 'Best Pace', pace, const Color(0xFF2EC4FF), const Color(0xFF0A6C99)),
      ('🔥', 'Longest Streak', '$bestStreak day${bestStreak == 1 ? '' : 's'}', Rb.orange,
          Rb.orangeEdge),
      ('🔋', 'Total Active Time', _duration(f.totalActiveSeconds), Rb.gold, Rb.goldEdge),
    ];

    final ach = <(String, String, bool)>[
      ('🏃', 'First Mile', km >= 1.6),
      ('🌟', '5K Hero', km >= 5),
      ('🏔️', '10K Legend', km >= 10),
      ('🔥', 'Week Streak', bestStreak >= 7),
      ('🛒', 'First Buy', bought),
      ('🦵', 'Iron Legs', sessions >= 10),
    ];

    return [
      const BlockText('📈 PERSONAL RECORDS', size: 14, stroke: 3.5),
      const SizedBox(height: 10),
      for (final r in records)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Block(
            color: Rb.panel,
            edge: Rb.panelEdge,
            depth: 5,
            radius: 12,
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Block(
                  color: r.$4,
                  edge: r.$5,
                  depth: 3,
                  radius: 10,
                  padding: EdgeInsets.zero,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(child: Text(r.$1, style: const TextStyle(fontSize: 21))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: BlockText(r.$2.toUpperCase(), size: 12, stroke: 3)),
                BlockText(r.$3, size: 15, stroke: 4, color: r.$4),
              ],
            ),
          ),
        ),
      const SizedBox(height: 6),
      const BlockText('🎖️ ACHIEVEMENTS', size: 14, stroke: 3.5),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1,
        children: [
          for (final a in ach)
            Block(
              color: a.$3 ? Rb.gold : Rb.panel,
              edge: a.$3 ? Rb.goldEdge : Rb.panelEdge,
              depth: 5,
              radius: 12,
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Opacity(
                    opacity: a.$3 ? 1 : 0.35,
                    child: Text(a.$3 ? a.$1 : '🔒', style: const TextStyle(fontSize: 28)),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: BlockText(a.$2.toUpperCase(),
                        size: 9,
                        stroke: 2.5,
                        color: a.$3 ? Colors.white : const Color(0xFF9AA0A6)),
                  ),
                ],
              ),
            ),
        ],
      ),
    ];
  }

  // ── helpers ──
  String _fmt(int n) => n
      .toString()
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  String _duration(int secs) {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}

/// Thick retro loading bar: hard black outline, segmented fill, no rounding.
class _RetroBar extends StatelessWidget {
  final double fraction;
  final double height;
  final Color color;

  const _RetroBar({
    required this.fraction,
    this.height = 30,
    this.color = const Color(0xFF39D353),
  });

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF15171A),
        border: Border.all(color: Colors.black, width: 3),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(0, 4), blurRadius: 0)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(1),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: f,
              child: Container(color: color),
            ),
            // glossy highlight on the filled part
            FractionallySizedBox(
              alignment: Alignment.topLeft,
              widthFactor: f,
              heightFactor: 0.32,
              child: Container(color: Colors.white.withValues(alpha: 0.3)),
            ),
            // 10 loading-bar segments
            Row(
              children: [
                for (var i = 0; i < 10; i++)
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: i == 9
                              ? BorderSide.none
                              : BorderSide(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  width: 2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
