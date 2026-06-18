import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onBackTap;

  const ProfileScreen({super.key, this.onBackTap});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _userData;
  bool _loading = true;

  static const Color bgDeep   = Color(0xFF060D0A);
  static const Color bgPanel  = Color(0xFF0D1A12);
  static const Color bgCard   = Color(0xFF122018);
  static const Color green    = Color(0xFF00FF6A);
  static const Color greenDim = Color(0xFF1A4D30);
  static const Color gold     = Color(0xFFFFD700);
  static const Color purple   = Color(0xFF9B59FF);
  static const Color red      = Color(0xFFFF4444);
  static const Color teal     = Color(0xFF00E5CC);
  static const Color textMain = Color(0xFFE8F5E9);
  static const Color textSub  = Color(0xFF6B8C72);

  static const Map<String, Color> rarityColor = {
    'Common'    : Color(0xFF9E9E9E),
    'Uncommon'  : Color(0xFF4CAF50),
    'Rare'      : Color(0xFF2196F3),
    'Epic'      : Color(0xFF9C27B0),
    'Legendary' : Color(0xFFFFD700),
    'Divine'    : Color(0xFFFF6B35),
  };

  final List<Map<String, dynamic>> _equippedGear = [
    {
      'slot'   : 'Weapon',
      'name'   : 'Verdant Blade',
      'rarity' : 'Legendary',
      'icon'   : '⚔️',
      'atk'    : 480,
      'spd'    : 120,
      'xpBonus': 25,
    },
    {
      'slot'   : 'Helmet',
      'name'   : 'Shadow Crown',
      'rarity' : 'Epic',
      'icon'   : '👑',
      'def'    : 210,
      'hp'     : 800,
      'xpBonus': 10,
    },
    {
      'slot'   : 'Armor',
      'name'   : 'Forest Plate',
      'rarity' : 'Rare',
      'icon'   : '🛡️',
      'def'    : 340,
      'hp'     : 1200,
      'xpBonus': 5,
    },
    {
      'slot'   : 'Boots',
      'name'   : 'Windrunner Treads',
      'rarity' : 'Epic',
      'icon'   : '👟',
      'spd'    : 280,
      'stam'   : 150,
      'xpBonus': 15,
    },
  ];

  int get _combatPower => (_userData?['level'] ?? 1) * 420 + 3850;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUser();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (mounted) {
        setState(() {
          _userData = doc.data() ?? {};
          _loading  = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: bgPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: red, width: 1),
        ),
        title: const Text('Sign Out',
            style: TextStyle(color: textMain, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(color: textSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: textSub)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: bgDeep,
        body: Center(child: CircularProgressIndicator(color: green)),
      );
    }

    final user          = FirebaseAuth.instance.currentUser;
    final username      = _userData?['username']     ?? user?.displayName ?? 'Hero';
    final level         = _userData?['level']        ?? 1;
    final xp            = (_userData?['xp']          ?? 0) as int;
    final xpNeeded      = level * 500;
    final coins         = _userData?['coins']        ?? 0;
    final gems          = _userData?['gems']         ?? 0;
    final souls         = _userData?['heroic_souls'] ?? 0;
    final totalKm       = (_userData?['total_km']    ?? 0.0) as double;
    final sessions      = _userData?['total_sessions'] ?? 0;
    final steps         = _userData?['total_steps']    ?? 0;
    final avatarUrl     = user?.photoURL;

    return Scaffold(
      backgroundColor: bgDeep,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _buildHeroBanner(
              username : username,
              level    : level,
              xp       : xp,
              xpNeeded : xpNeeded,
              avatarUrl: avatarUrl,
            ),
          ),
          SliverToBoxAdapter(child: _buildCombatPowerStrip()),
          SliverToBoxAdapter(
            child: _buildCurrencyRow(coins: coins, gems: gems, souls: souls),
          ),
          SliverToBoxAdapter(
            child: TabBar(
              controller          : _tabController,
              indicatorColor      : green,
              labelColor          : green,
              unselectedLabelColor: textSub,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: const [
                Tab(text: 'STATS'),
                Tab(text: 'GEAR'),
                Tab(text: 'RECORDS'),
              ],
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: true,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildStatsTab(
                    totalKm : totalKm,
                    sessions: sessions,
                    steps   : steps,
                    level   : level),
                _buildGearTab(),
                _buildRecordsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBanner({
    required String username,
    required int level,
    required int xp,
    required int xpNeeded,
    String? avatarUrl,
  }) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin  : Alignment.topCenter,
          end    : Alignment.bottomCenter,
          colors : [Color(0xFF0A2010), bgDeep],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 0),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => widget.onBackTap?.call(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color       : bgCard,
                    borderRadius: BorderRadius.circular(10),
                    border      : Border.all(color: greenDim),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new, color: green, size: 18),
                ),
              ),
              const Spacer(),
              const Text('PROFILE',
                  style: TextStyle(
                      color        : green,
                      fontSize     : 14,
                      fontWeight   : FontWeight.bold,
                      letterSpacing: 4)),
              const Spacer(),
              GestureDetector(
                onTap: _signOut,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color       : bgCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF4D1515)),
                  ),
                  child: const Icon(Icons.logout, color: red, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [green, teal],
                    begin  : Alignment.topLeft,
                    end    : Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                        color     : green.withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 2),
                  ],
                ),
                child: CircleAvatar(
                  radius         : 52,
                  backgroundColor: bgCard,
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null
                      ? const Icon(Icons.person, color: green, size: 52)
                      : null,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color    : gold,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: gold.withValues(alpha: 0.5), blurRadius: 8)],
                ),
                child: Text(
                  'LV $level',
                  style: const TextStyle(
                      color        : Colors.black,
                      fontWeight   : FontWeight.w900,
                      fontSize     : 11,
                      letterSpacing: 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(username,
              style: const TextStyle(
                  color        : textMain,
                  fontSize     : 22,
                  fontWeight   : FontWeight.bold,
                  letterSpacing: 1.5)),
          const SizedBox(height: 4),
          Text(FirebaseAuth.instance.currentUser?.email ?? '',
              style: const TextStyle(color: textSub, fontSize: 12)),
          const SizedBox(height: 16),
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('EXP  $xp / $xpNeeded',
                      style: const TextStyle(color: textSub, fontSize: 12)),
                  Text(
                      '${((xp / xpNeeded) * 100).clamp(0, 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                          color     : green,
                          fontSize  : 12,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value     : (xp / xpNeeded).clamp(0.0, 1.0),
                  minHeight : 8,
                  backgroundColor: greenDim,
                  valueColor: const AlwaysStoppedAnimation<Color>(green),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildCombatPowerStrip() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0A3D), Color(0xFF0D1A12)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: purple.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(color: purple.withValues(alpha: 0.15), blurRadius: 12),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, color: purple, size: 26),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('COMBAT POWER',
                  style: TextStyle(color: textSub, fontSize: 10, letterSpacing: 2)),
              SizedBox(height: 2),
              Text('HERO STRENGTH RATING',
                  style: TextStyle(color: textSub, fontSize: 9)),
            ],
          ),
          const Spacer(),
          Text(
            _combatPower.toString().replaceAllMapped(
                RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                (m) => '${m[1]},'),
            style: const TextStyle(
                color        : purple,
                fontSize     : 28,
                fontWeight   : FontWeight.w900,
                letterSpacing: 1),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrencyRow({required int coins, required int gems, required int souls}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          _currencyChip('💰', '$coins', 'Coins', gold),
          const SizedBox(width: 8),
          _currencyChip('💎', '$gems', 'Gems', teal),
          const SizedBox(width: 8),
          _currencyChip('🔮', '$souls', 'Souls', purple),
        ],
      ),
    );
  }

  Widget _currencyChip(String icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color       : bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    color     : color,
                    fontWeight: FontWeight.bold,
                    fontSize  : 14)),
            Text(label,
                style: const TextStyle(color: textSub, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsTab({
    required double totalKm,
    required int sessions,
    required int steps,
    required int level,
  }) {
    final stats = [
      _SlayerStat('⚔️', 'Attack',
          desc : 'Gear ATK + Level bonus',
          value: level * 42 + 480,
          max  : level * 42 + 2000,
          color: red),
      _SlayerStat('🛡️', 'Defense',
          desc : 'Gear DEF + Stamina',
          value: level * 28 + 340,
          max  : level * 28 + 1500,
          color: teal),
      _SlayerStat('💨', 'Speed',
          desc : 'Running pace factor',
          value: (totalKm * 8).round().clamp(0, 1200),
          max  : 1200,
          color: green),
      _SlayerStat('❤️', 'HP',
          desc : 'Total health pool',
          value: level * 200 + 1200,
          max  : level * 200 + 8000,
          color: red),
      _SlayerStat('⚡', 'Stamina',
          desc : 'Endurance from sessions',
          value: sessions * 12 + 150,
          max  : 2000,
          color: gold),
      _SlayerStat('✨', 'XP Bonus',
          desc  : 'Extra XP per run',
          value : 55,
          max   : 200,
          color : purple,
          suffix: '%'),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          _summaryCard('🏃', '${totalKm.toStringAsFixed(1)} km', 'Total Distance', green),
          const SizedBox(width: 10),
          _summaryCard('👟', '${(steps / 1000).toStringAsFixed(1)}k', 'Total Steps', teal),
          const SizedBox(width: 10),
          _summaryCard('🗓️', '$sessions', 'Sessions', gold),
        ]),
        const SizedBox(height: 20),
        const _SectionHeader(label: 'HERO STATS', icon: Icons.shield),
        const SizedBox(height: 10),
        ...stats.map((s) => _buildStatBar(s)),
      ],
    );
  }

  Widget _summaryCard(String icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color       : bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
            Text(label,
                style: const TextStyle(color: textSub, fontSize: 9, letterSpacing: 0.5),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBar(_SlayerStat stat) {
    final ratio = (stat.value / stat.max).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color       : bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: stat.color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${stat.icon}  ${stat.name}',
                  style: TextStyle(
                      color     : stat.color,
                      fontWeight: FontWeight.bold,
                      fontSize  : 13)),
              const Spacer(),
              Text('${stat.value}${stat.suffix ?? ''}',
                  style: TextStyle(
                      color     : stat.color,
                      fontWeight: FontWeight.w900,
                      fontSize  : 16)),
            ],
          ),
          const SizedBox(height: 4),
          Text(stat.desc, style: const TextStyle(color: textSub, fontSize: 10)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value          : ratio,
              minHeight      : 6,
              backgroundColor: stat.color.withValues(alpha: 0.12),
              valueColor     : AlwaysStoppedAnimation<Color>(stat.color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGearTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionHeader(label: 'EQUIPPED GEAR', icon: Icons.star),
        const SizedBox(height: 10),
        ..._equippedGear.map(_buildGearCard),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => Navigator.pushNamed(context, '/equipment'),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              border      : Border.all(color: green),
              borderRadius: BorderRadius.circular(14),
              color       : greenDim.withValues(alpha: 0.3),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.swap_horiz, color: green),
                SizedBox(width: 8),
                Text('MANAGE EQUIPMENT',
                    style: TextStyle(
                        color        : green,
                        fontWeight   : FontWeight.bold,
                        letterSpacing: 2,
                        fontSize     : 13)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGearCard(Map<String, dynamic> gear) {
    final rarity = gear['rarity'] as String;
    final color  = rarityColor[rarity] ?? textSub;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color       : bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 10)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width : 52,
              height: 52,
              decoration: BoxDecoration(
                color       : color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.6)),
              ),
              child: Center(child: Text(gear['icon'], style: const TextStyle(fontSize: 26))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(gear['name'],
                          style: const TextStyle(
                              color     : textMain,
                              fontWeight: FontWeight.bold,
                              fontSize  : 14)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color       : color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color.withValues(alpha: 0.4)),
                        ),
                        child: Text(rarity,
                            style: TextStyle(
                                color        : color,
                                fontSize     : 9,
                                fontWeight   : FontWeight.bold,
                                letterSpacing: 0.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(gear['slot'], style: const TextStyle(color: textSub, fontSize: 11)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 4, children: _gearStatChips(gear)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _gearStatChips(Map<String, dynamic> gear) {
    final chips = <Widget>[];
    const labels = {
      'atk'    : ('⚔️ ATK', red),
      'def'    : ('🛡️ DEF', teal),
      'spd'    : ('💨 SPD', green),
      'hp'     : ('❤️ HP',  Color(0xFFFF6B6B)),
      'stam'   : ('⚡ STAM', gold),
      'xpBonus': ('✨ XP+', purple),
    };
    for (final entry in labels.entries) {
      if (gear.containsKey(entry.key)) {
        final val   = gear[entry.key];
        final label = entry.value.$1;
        final color = entry.value.$2;
        chips.add(Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color       : color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('$label +$val',
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        ));
      }
    }
    return chips;
  }

  // ── RECORDS Tab — real Firestore data ────────────────────────────────────
  Widget _buildRecordsTab() {
    // Pull real values from Firestore, fall back to 0 / defaults
    final longestRunKm  = (_userData?['longest_run_km']   ?? 0.0) as double;
    final bestPaceSecs  = (_userData?['best_pace_secs']   ?? 0)   as int;   // stored as total seconds per km
    final longestStreak = (_userData?['longest_streak']   ?? 0)   as int;
    final coinsEarned   = (_userData?['coins']            ?? 0)   as int;

    // Format pace as m:ss /km
    String paceLabel = '—';
    if (bestPaceSecs > 0) {
      final m = bestPaceSecs ~/ 60;
      final s = bestPaceSecs  % 60;
      paceLabel = '$m:${s.toString().padLeft(2, '0')} /km';
    }

    final longestRunLabel  = longestRunKm  > 0 ? '${longestRunKm.toStringAsFixed(1)} km' : '—';
    final longestStreakLabel = '$longestStreak day${longestStreak == 1 ? '' : 's'}';
    final coinsLabel       = coinsEarned.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

    final records = [
      _Record('🏆', 'Longest Run',    longestRunLabel,   green),
      _Record('⚡', 'Best Pace',       paceLabel,         teal),
      _Record('🔥', 'Longest Streak', longestStreakLabel, gold),
      _Record('💰', 'Coins Earned',   coinsLabel,        gold),
    ];

    // Achievement unlock conditions based on real stats
    final totalKm  = (_userData?['total_km']       ?? 0.0) as double;
    final sessions = (_userData?['total_sessions'] ?? 0)   as int;

    final ach = [
      ('🏃', 'First Mile',  totalKm >= 1.6),
      ('🌟', '5K Hero',     totalKm >= 5.0),
      ('💪', '10K Legend',  totalKm >= 10.0),
      ('🔥', 'Week Streak', longestStreak >= 7),
      ('👑', 'Gacha King',  false),             // future: track gacha pulls
      ('⚔️', 'Survivor',    sessions >= 10),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionHeader(label: 'PERSONAL RECORDS', icon: Icons.emoji_events),
        const SizedBox(height: 10),
        ...records.map((r) => _buildRecordRow(r)),
        const SizedBox(height: 20),
        const _SectionHeader(label: 'ACHIEVEMENTS', icon: Icons.military_tech),
        const SizedBox(height: 10),
        _buildAchievementGrid(ach),
      ],
    );
  }

  Widget _buildRecordRow(_Record r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color       : bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: r.color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Text(r.icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 14),
          Text(r.label, style: const TextStyle(color: textSub, fontSize: 13)),
          const Spacer(),
          Text(r.value,
              style: TextStyle(
                  color     : r.color,
                  fontWeight: FontWeight.bold,
                  fontSize  : 16)),
        ],
      ),
    );
  }

  Widget _buildAchievementGrid(List<(String, String, bool)> ach) {
    return GridView.builder(
      shrinkWrap: true,
      physics   : const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount  : 3,
          crossAxisSpacing: 10,
          mainAxisSpacing : 10,
          childAspectRatio: 1),
      itemCount  : ach.length,
      itemBuilder: (_, i) {
        final (icon, label, unlocked) = ach[i];
        return Container(
          decoration: BoxDecoration(
            color       : unlocked ? bgCard : bgPanel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: unlocked ? gold.withValues(alpha: 0.5) : greenDim),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(icon,
                  style: TextStyle(
                      fontSize: 28,
                      color: unlocked ? null : const Color(0xFF2A2A2A))),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      color     : unlocked ? gold : textSub,
                      fontSize  : 10,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              if (!unlocked)
                const Icon(Icons.lock, color: textSub, size: 12),
            ],
          ),
        );
      },
    );
  }
}

class _SlayerStat {
  final String  icon;
  final String  name;
  final String  desc;
  final int     value;
  final int     max;
  final Color   color;
  final String? suffix;

  const _SlayerStat(this.icon, this.name,
      {required this.desc,
      required this.value,
      required this.max,
      required this.color,
      this.suffix});
}

class _Record {
  final String icon;
  final String label;
  final String value;
  final Color  color;
  const _Record(this.icon, this.label, this.value, this.color);
}

class _SectionHeader extends StatelessWidget {
  final String   label;
  final IconData icon;

  const _SectionHeader({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF00FF6A), size: 16),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                color        : Color(0xFF00FF6A),
                fontSize     : 11,
                fontWeight   : FontWeight.bold,
                letterSpacing: 3)),
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, color: const Color(0xFF1A4D30))),
      ],
    );
  }
}