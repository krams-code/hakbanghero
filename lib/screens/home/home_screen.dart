import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../run/run_tracking_screen.dart';
import '../../models/daily_quest_definitions.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onProfileTap;
  const HomeScreen({super.key, this.onProfileTap});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _portalController;
  late AnimationController _pulseController;
  late AnimationController _entryController;
  late Animation<double> _portalRotation;
  late Animation<double> _portalGlow;
  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;

  @override
  void initState() {
    super.initState();

    _portalController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _portalRotation = Tween<double>(begin: 0, end: 1).animate(_portalController);
    _portalGlow = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _entryFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOut),
    );
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _portalController.dispose();
    _pulseController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  void _onStartRun() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => const RunTrackingScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          ),
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
    // No manual reload needed — StreamBuilder auto-updates when Firestore changes
  }

  // ── Stage name & dungeon text derived from total_km ───────────────────────
  static _StageInfo _stageFromKm(double km) {
    if (km < 5)   return const _StageInfo('1-1', 'THE VERDANT VALE',    'Reach 5 km to unlock next stage');
    if (km < 10)  return const _StageInfo('1-2', 'THE MISTY MARSHES',   'Reach 10 km to unlock next stage');
    if (km < 20)  return const _StageInfo('1-3', 'THE HAUNTED HIGHLANDS','Reach 20 km to unlock next stage');
    if (km < 35)  return const _StageInfo('2-1', 'THE ASHEN PEAKS',     'Reach 35 km to unlock next stage');
    if (km < 55)  return const _StageInfo('2-2', 'THE CRYSTAL CAVERNS', 'Reach 55 km to unlock next stage');
    if (km < 80)  return const _StageInfo('2-3', 'THE SHADOW FORTRESS', 'Reach 80 km to unlock next stage');
    if (km < 120) return const _StageInfo('3-1', 'THE FROZEN TUNDRA',   'Reach 120 km to unlock next stage');
    return const _StageInfo('3-2', 'THE DRAGON\'S LAIR', 'Max unlocked stage — legendary!');
  }

  String _todayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF060C06),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00FF41))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF060C06),
      // ── Single StreamBuilder drives the ENTIRE home screen ────────────────
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snapshot) {
          // Show spinner only on the very first load
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF00FF41)),
            );
          }

          final data = snapshot.data!.exists
              ? (snapshot.data!.data() as Map<String, dynamic>)
              : <String, dynamic>{};

          // ── Parse all user fields ─────────────────────────────────────────
          final username = data['username'] as String? ??
              FirebaseAuth.instance.currentUser?.displayName ??
              'Hero';
          final level    = (data['level'] as num?)?.toInt() ?? 1;
          final xp       = (data['xp'] as num?)?.toInt() ?? 0;
          final totalKm  = (data['total_km'] as num?)?.toDouble() ?? 0.0;
          final sessions = (data['total_sessions'] as num?)?.toInt() ?? 0;

          final xpForNext  = level * 500;
          final xpProgress = (xp % xpForNext) / xpForNext;
          final stage      = _stageFromKm(totalKm);

          // ── Daily quest progress ──────────────────────────────────────────
          final todayStr   = _todayDateString();
          final storedDate = data['daily_progress_date'] as String? ?? '';
          final dailyKm    = storedDate == todayStr
              ? (data['daily_progress_km'] as num?)?.toDouble() ?? 0.0
              : 0.0;
          final claimedMap = storedDate == todayStr
              ? Map<String, dynamic>.from(data['daily_quests_claimed'] as Map? ?? {})
              : <String, dynamic>{};

          return FadeTransition(
            opacity: _entryFade,
            child: SlideTransition(
              position: _entrySlide,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildTopBar(username: username, level: level),
                  ),
                  SliverToBoxAdapter(
                    child: _buildXPBar(xp: xp, xpForNext: xpForNext, xpProgress: xpProgress),
                  ),
                  SliverToBoxAdapter(
                    child: _buildStatsRow(
                      totalKm: totalKm,
                      sessions: sessions,
                      stage: stage,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _buildPortalSection(stage: stage),
                  ),
                  SliverToBoxAdapter(
                    child: _buildActiveQuests(
                      dailyKm: dailyKm,
                      claimedMap: claimedMap,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _buildRecentActivity(uid: uid, sessions: sessions),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────
  Widget _buildTopBar({required String username, required int level}) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 16, right: 16, bottom: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0A1A0A),
            const Color(0xFF060C06).withOpacity(0),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onProfileTap,
            child: Row(
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A4A1A), Color(0xFF0D2A0D)],
                    ),
                    border: Border.all(color: const Color(0xFF00FF41), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00FF41).withOpacity(0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.person, color: Color(0xFF00FF41), size: 20),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      style: const TextStyle(
                        color: Color(0xFFE8FFE8), fontSize: 15,
                        fontWeight: FontWeight.w700, letterSpacing: 0.5,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00FF41).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: const Color(0xFF00FF41).withOpacity(0.4),
                            ),
                          ),
                          child: Text(
                            'LVL $level',
                            style: const TextStyle(
                              color: Color(0xFF00FF41), fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'HERO',
                          style: TextStyle(
                            color: Color(0xFF4A8A4A), fontSize: 10, letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  // ── XP bar ────────────────────────────────────────────────────────────────
  Widget _buildXPBar({
    required int xp,
    required int xpForNext,
    required double xpProgress,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'EXP  $xp / $xpForNext',
                style: const TextStyle(
                  color: Color(0xFF4A8A4A), fontSize: 11, letterSpacing: 0.5,
                ),
              ),
              Text(
                '${(xpProgress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Color(0xFF00FF41), fontSize: 11, fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: const Color(0xFF1A2A1A),
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: xpProgress.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00FF41), Color(0xFF00CC33)],
                  ),
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00FF41).withOpacity(0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Stats row — all live from Firestore ───────────────────────────────────
  Widget _buildStatsRow({
    required double totalKm,
    required int sessions,
    required _StageInfo stage,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          _StatCard(
            label: 'TOTAL KM',
            value: totalKm.toStringAsFixed(1),
            unit: 'km',
            icon: Icons.route,
            color: const Color(0xFF00FF41),
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: 'SESSIONS',
            value: '$sessions',
            unit: 'runs',
            icon: Icons.flag,
            color: const Color(0xFF00CFFF),
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: 'DUNGEON',
            value: stage.id,
            unit: 'stage',
            icon: Icons.castle,
            color: const Color(0xFFFFD700),
          ),
        ],
      ),
    );
  }

  // ── Portal / dungeon section ──────────────────────────────────────────────
  Widget _buildPortalSection({required _StageInfo stage}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'DUNGEON ENTRANCE',
                style: TextStyle(
                  color: Color(0xFF4A8A4A), fontSize: 11,
                  letterSpacing: 2, fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
                ),
                child: Text(
                  'STAGE ${stage.id}',
                  style: const TextStyle(
                    color: Color(0xFFFFD700), fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () {},
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF1A4A1A), width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.8,
                        colors: [Color(0xFF0D2A1A), Color(0xFF060C06)],
                      ),
                    ),
                  ),
                  CustomPaint(size: Size.infinite, painter: _GridPainter()),
                  AnimatedBuilder(
                    animation: _portalGlow,
                    builder: (_, __) => Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 160, height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6600CC)
                                      .withOpacity(0.15 * _portalGlow.value),
                                  blurRadius: 40, spreadRadius: 20,
                                ),
                              ],
                            ),
                          ),
                          AnimatedBuilder(
                            animation: _portalRotation,
                            builder: (_, __) => Transform.rotate(
                              angle: _portalRotation.value * 2 * 3.14159,
                              child: Container(
                                width: 120, height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF6600CC).withOpacity(0.6),
                                    width: 2,
                                  ),
                                ),
                                child: CustomPaint(painter: _DashedCirclePainter()),
                              ),
                            ),
                          ),
                          Container(
                            width: 90, height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Color.lerp(
                                    const Color(0xFF8800FF),
                                    const Color(0xFF4400CC),
                                    _portalGlow.value,
                                  )!,
                                  const Color(0xFF1A0033),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF8800FF)
                                      .withOpacity(0.5 * _portalGlow.value),
                                  blurRadius: 20, spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.castle,
                              color: Colors.white
                                  .withOpacity(0.6 + 0.3 * _portalGlow.value),
                              size: 36,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16, left: 0, right: 0,
                    child: Column(
                      children: [
                        Text(
                          stage.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFCC88FF), fontSize: 12,
                            fontWeight: FontWeight.w700, letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          stage.hint,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF4A8A4A), fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 12, right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'TAP TO ENTER',
                        style: TextStyle(
                          color: Color(0xFF888888), fontSize: 9, letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity, height: 56,
            child: ElevatedButton(
              onPressed: _onStartRun,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00FF41), Color(0xFF00BB30)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00FF41).withOpacity(0.35),
                      blurRadius: 16, offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Container(
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.directions_run, color: Color(0xFF0A0F0A), size: 22),
                      SizedBox(width: 10),
                      Text(
                        'START RUN',
                        style: TextStyle(
                          color: Color(0xFF0A0F0A), fontSize: 16,
                          fontWeight: FontWeight.w900, letterSpacing: 3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Active quests — driven by the parent StreamBuilder ────────────────────
  Widget _buildActiveQuests({
    required double dailyKm,
    required Map<String, dynamic> claimedMap,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'ACTIVE QUESTS',
                style: TextStyle(
                  color: Color(0xFF4A8A4A), fontSize: 11,
                  letterSpacing: 2, fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.4)),
                ),
                child: Text(
                  '${kDailyQuests.length} ACTIVE',
                  style: const TextStyle(
                    color: Color(0xFFFF6B35), fontSize: 9,
                    fontWeight: FontWeight.w700, letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...kDailyQuests.map((quest) {
            final claimed  = claimedMap[quest.id] == true;
            final progress = (dailyKm / quest.thresholdKm).clamp(0.0, 1.0);
            return _QuestCard(
              quest:    quest,
              progress: progress,
              claimed:  claimed,
              dailyKm:  dailyKm,
            );
          }),
        ],
      ),
    );
  }

  // ── Recent activity ───────────────────────────────────────────────────────
  Widget _buildRecentActivity({required String uid, required int sessions}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RECENT ACTIVITY',
            style: TextStyle(
              color: Color(0xFF4A8A4A), fontSize: 11,
              letterSpacing: 2, fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (sessions == 0)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1A0D),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1A3A1A)),
              ),
              child: const Center(
                child: Column(
                  children: [
                    Icon(Icons.directions_run, color: Color(0xFF2A4A2A), size: 32),
                    SizedBox(height: 8),
                    Text(
                      'No runs yet — start your first session!',
                      style: TextStyle(color: Color(0xFF3A6A3A), fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            _RecentActivityList(uid: uid),
        ],
      ),
    );
  }
}

// ─── Stage info model ─────────────────────────────────────────────────────────
class _StageInfo {
  final String id;
  final String name;
  final String hint;
  const _StageInfo(this.id, this.name, this.hint);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Quest card
// ─────────────────────────────────────────────────────────────────────────────
class _QuestCard extends StatelessWidget {
  final DailyQuest quest;
  final double progress;
  final bool claimed;
  final double dailyKm;

  const _QuestCard({
    required this.quest,
    required this.progress,
    required this.claimed,
    required this.dailyKm,
  });

  Color get _progressColor {
    if (claimed) return const Color(0xFF4A8A4A);
    if (progress >= 1.0) return const Color(0xFF00FF41);
    if (progress >= 0.5) return const Color(0xFFFFD700);
    return const Color(0xFFFF6B35);
  }

  @override
  Widget build(BuildContext context) {
    final kmText =
        '${dailyKm.toStringAsFixed(2)} / ${quest.thresholdKm.toStringAsFixed(1)} km';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A0D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: claimed
              ? const Color(0xFF2A4A2A)
              : _progressColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: _progressColor.withOpacity(claimed ? 0.06 : 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _progressColor.withOpacity(claimed ? 0.2 : 0.35),
              ),
            ),
            child: claimed
                ? const Icon(Icons.check, color: Color(0xFF4A8A4A), size: 18)
                : Icon(quest.icon, color: _progressColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      quest.title,
                      style: TextStyle(
                        color: claimed
                            ? const Color(0xFF4A6A4A)
                            : const Color(0xFFD0EED0),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: claimed
                            ? const Color(0xFF1A2A1A)
                            : const Color(0xFF00CFFF).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        claimed
                            ? '✓ ${quest.crystalReward} 💎'
                            : '+${quest.crystalReward} 💎',
                        style: TextStyle(
                          color: claimed
                              ? const Color(0xFF3A6A3A)
                              : const Color(0xFF00CFFF),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  claimed ? 'Completed today!' : quest.description,
                  style: TextStyle(
                    color: claimed
                        ? const Color(0xFF3A6A3A)
                        : const Color(0xFF4A7A4A),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 6),
                if (!claimed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      kmText,
                      style: TextStyle(
                        color: _progressColor.withOpacity(0.8),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Stack(
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2A1A),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: progress,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: _progressColor,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: claimed
                              ? []
                              : [
                                  BoxShadow(
                                    color: _progressColor.withOpacity(0.4),
                                    blurRadius: 4,
                                  ),
                                ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Recent activity list
// ─────────────────────────────────────────────────────────────────────────────
class _RecentActivityList extends StatelessWidget {
  final String uid;
  const _RecentActivityList({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('activities')
          .orderBy('startTime', descending: true)
          .limit(3)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1A0D),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF1A3A1A)),
            ),
            child: const Text(
              'Activity history coming soon',
              style: TextStyle(color: Color(0xFF4A8A4A), fontSize: 13),
            ),
          );
        }

        return Column(
          children: snapshot.data!.docs.map((doc) {
            final s     = _parseSession(doc);
            final color = _colorForType(s['type'] as String);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1A0D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Text(_emojiForType(s['type'] as String),
                      style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (s['type'] as String).toUpperCase(),
                          style: TextStyle(
                              color: color, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${(s['distanceKm'] as double).toStringAsFixed(2)} km  •  ${s['duration']}',
                          style: const TextStyle(
                              color: Color(0xFF4A7A4A), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '+${s['xp']} XP',
                    style: const TextStyle(
                        color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Map<String, dynamic> _parseSession(DocumentSnapshot doc) {
    final d    = doc.data() as Map<String, dynamic>;
    final secs = (d['durationSeconds'] as num).toInt();
    return {
      'type':       d['type'] as String? ?? 'run',
      'distanceKm': (d['distanceKm'] as num).toDouble(),
      'duration':   '${secs ~/ 60}m ${secs % 60}s',
      'xp':         (d['xpEarned'] as num).toInt(),
    };
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'walk': return const Color(0xFF00CFFF);
      case 'jog':  return const Color(0xFFFFD700);
      default:     return const Color(0xFF00FF41);
    }
  }

  String _emojiForType(String type) {
    switch (type) {
      case 'walk': return '🚶';
      case 'jog':  return '🏃';
      default:     return '⚡';
    }
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1A0D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 18, fontWeight: FontWeight.w800)),
            Text(unit,
                style: const TextStyle(color: Color(0xFF3A5A3A), fontSize: 10)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF3A6A3A), fontSize: 9, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

// ─── Custom painters ──────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A3A1A).withOpacity(0.3)
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _DashedCirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF8800FF).withOpacity(0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const dashCount   = 16;
    const gapFraction = 0.4;
    const pi2         = 2 * 3.14159265;
    final r  = size.width / 2;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final dashLen = pi2 / dashCount * (1 - gapFraction);
    final gapLen  = pi2 / dashCount * gapFraction;

    double angle = 0;
    for (int i = 0; i < dashCount; i++) {
      final path = Path();
      path.addArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        angle, dashLen,
      );
      canvas.drawPath(path, paint);
      angle += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(_) => false;
}