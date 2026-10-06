import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../run/run_tracking_screen.dart';
import '../../models/daily_quest_definitions.dart';
import '../../widgets/avatar_layer_stack.dart' show kSpriteWidth, kSpriteHeight;
import '../../widgets/avatar_preview.dart';
import '../../widgets/block_ui.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onProfileTap;
  const HomeScreen({super.key, this.onProfileTap});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _entryController;
  late AnimationController _idleController;
  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;

  @override
  void initState() {
    super.initState();

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    // stepped idle bob for the avatar
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

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
    _entryController.dispose();
    _idleController.dispose();
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
  }

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
        backgroundColor: Rb.bg,
        body: Center(child: CircularProgressIndicator(color: Rb.green)),
      );
    }

    return Scaffold(
      backgroundColor: Rb.bg,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: Rb.green));
          }

          final data = snapshot.data!.exists
              ? (snapshot.data!.data() as Map<String, dynamic>)
              : <String, dynamic>{};

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
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.of(context).padding.top + 12,
                  16,
                  24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHud(
                      username: username,
                      level: level,
                      xp: xp,
                      xpForNext: xpForNext,
                      xpProgress: xpProgress,
                    ),
                    const SizedBox(height: 16),
                    _buildStageHeader(stage),
                    const SizedBox(height: 12),
                    _buildPortal(stage: stage, data: data),
                    const SizedBox(height: 14),
                    _buildActionButton(),
                    const SizedBox(height: 18),
                    _buildQuests(dailyKm: dailyKm, claimedMap: claimedMap),
                    const SizedBox(height: 12),
                    _buildRecentActivity(uid: uid, sessions: sessions),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ───────────────────────── HUD ─────────────────────────

  Widget _buildHud({
    required String username,
    required int level,
    required int xp,
    required int xpForNext,
    required double xpProgress,
  }) {
    return Block(
      color: Rb.hud,
      edge: Rb.hudEdge,
      depth: 6,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              PressBlock(
                color: Rb.blue,
                edge: Rb.blueEdge,
                depth: 4,
                radius: 12,
                padding: const EdgeInsets.all(8),
                onTap: widget.onProfileTap,
                child: const Icon(Icons.person, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BlockText(username, size: 18, maxLines: 1),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Block(
                          color: Rb.green,
                          edge: Rb.greenEdge,
                          depth: 3,
                          radius: 8,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          child: BlockText('LVL $level', size: 11, stroke: 3),
                        ),
                        const SizedBox(width: 8),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 3),
                          child: Text(
                            'HERO',
                            style: TextStyle(
                              color: Color(0xFF2B2D2F),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
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
          const SizedBox(height: 12),
          Row(
            children: [
              BlockText('EXP $xp / $xpForNext', size: 11, stroke: 3),
              const Spacer(),
              BlockText('${(xpProgress * 100).toStringAsFixed(0)}%',
                  size: 11, stroke: 3, color: Rb.neon),
            ],
          ),
          const SizedBox(height: 6),
          BlockBar(value: xpProgress, height: 22),
        ],
      ),
    );
  }

  // ───────────────────────── stage header ─────────────────────────

  Widget _buildStageHeader(_StageInfo stage) {
    return Row(
      children: [
        const BlockText('DUNGEON ENTRANCE', size: 13, stroke: 3.5),
        const Spacer(),
        Block(
          color: Rb.gold,
          edge: Rb.goldEdge,
          depth: 4,
          radius: 10,
          gloss: true,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: BlockText('⭐ STAGE ${stage.id}', size: 12, stroke: 3),
        ),
      ],
    );
  }

  // ───────────────────────── portal viewport ─────────────────────────

  Widget _buildPortal({
    required _StageInfo stage,
    required Map<String, dynamic> data,
  }) {
    final world = int.tryParse(stage.id.split('-').first) ?? 1;
    final bgId = data['background_id'] as String?;
    final reduce = MediaQuery.of(context).disableAnimations;

    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.clamp(0.0, 360.0).toDouble();
      final h = w * 1.1;

      return Center(
        child: SizedBox(
          width: w,
          child: Column(
            children: [
              // wooden frame
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  height: h,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Rb.wood,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Rb.woodEdge, width: 3),
                    boxShadow: const [BoxShadow(color: Rb.woodEdge, offset: Offset(0, 8))],
                  ),
                  child: Stack(
                    children: [
                      // inner viewport
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Rb.woodEdge, width: 3),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                BlockBackground(
                                  id: bgId,
                                  fallback: LandscapeTheme.forWorld(world),
                                ),
                                AnimatedBuilder(
                                  animation: _idleController,
                                  builder: (_, child) {
                                    final dy = reduce
                                        ? 0.0
                                        : (_idleController.value < 0.5 ? 0.0 : -3.0);
                                    return Transform.translate(
                                        offset: Offset(0, dy), child: child);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                                    child: FittedBox(
                                      fit: BoxFit.contain,
                                      clipBehavior: Clip.none,
                                      child: SizedBox(
                                        width: kSpriteWidth,
                                        height: kSpriteHeight + 48,
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            // 44px headroom so tall hair isn't clipped
                                            Positioned(
                                              left: 0,
                                              top: 44,
                                              width: kSpriteWidth,
                                              height: kSpriteHeight,
                                              child: AvatarPreview.fromData(
                                                data,
                                                ownerUid: FirebaseAuth.instance.currentUser?.uid,
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
                          ),
                        ),
                      ),
                      // metal nails in the corners
                      for (final a in const [
                        Alignment.topLeft,
                        Alignment.topRight,
                        Alignment.bottomLeft,
                        Alignment.bottomRight,
                      ])
                        Align(
                          alignment: a,
                          child: Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.all(1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD6D6D6),
                              shape: BoxShape.circle,
                              border: Border.all(color: Rb.woodEdge, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // name plate
              Block(
                color: Rb.slate,
                edge: Rb.slateEdge,
                depth: 5,
                radius: 14,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    children: [
                      BlockText(stage.name,
                          size: 15, color: Rb.gold, align: TextAlign.center, maxLines: 1),
                      const SizedBox(height: 4),
                      Text(
                        stage.hint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  // ───────────────────────── action button ─────────────────────────

  Widget _buildActionButton() {
    return PressBlock(
      color: Rb.neon,
      edge: Rb.greenEdge,
      depth: 10,
      radius: 18,
      padding: const EdgeInsets.symmetric(vertical: 20),
      onTap: _onStartRun,
      child: const Center(child: BlockText('⚔️ ENTER DUNGEON', size: 24, stroke: 5)),
    );
  }

  // ───────────────────────── quests ─────────────────────────

  Widget _buildQuests({
    required double dailyKm,
    required Map<String, dynamic> claimedMap,
  }) {
    return Block(
      color: Rb.slate,
      edge: Rb.slateEdge,
      depth: 6,
      radius: 18,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const BlockText('🎒 ACTIVE QUESTS', size: 14, stroke: 3.5),
              const Spacer(),
              Block(
                color: Rb.orange,
                edge: Rb.orangeEdge,
                depth: 3,
                radius: 8,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: BlockText('${kDailyQuests.length} ACTIVE', size: 10, stroke: 3),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...kDailyQuests.map((quest) {
            final claimed = claimedMap[quest.id] == true;
            final progress = (dailyKm / quest.thresholdKm).clamp(0.0, 1.0).toDouble();
            return _QuestSlot(
              quest: quest,
              progress: progress,
              claimed: claimed,
              dailyKm: dailyKm,
            );
          }),
        ],
      ),
    );
  }

  // ───────────────────────── recent activity ─────────────────────────

  Widget _buildRecentActivity({required String uid, required int sessions}) {
    return Block(
      color: Rb.slate,
      edge: Rb.slateEdge,
      depth: 6,
      radius: 18,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BlockText('📜 RECENT ACTIVITY', size: 14, stroke: 3.5),
          const SizedBox(height: 12),
          if (sessions == 0)
            Block(
              color: Rb.slot,
              edge: Rb.slateEdge,
              depth: 4,
              radius: 12,
              padding: const EdgeInsets.all(16),
              child: const Center(
                child: Column(
                  children: [
                    Text('🏃', style: TextStyle(fontSize: 30)),
                    SizedBox(height: 6),
                    Text(
                      'No runs yet — start your first session!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
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

class _StageInfo {
  final String id;
  final String name;
  final String hint;
  const _StageInfo(this.id, this.name, this.hint);
}

// ───────────────────────── Quest slot ─────────────────────────

class _QuestSlot extends StatelessWidget {
  final DailyQuest quest;
  final double progress;
  final bool claimed;
  final double dailyKm;

  const _QuestSlot({
    required this.quest,
    required this.progress,
    required this.claimed,
    required this.dailyKm,
  });

  Color get _color {
    if (claimed) return Rb.silverEdge;
    if (progress >= 1.0) return Rb.green;
    if (progress >= 0.5) return Rb.gold;
    return Rb.orange;
  }

  @override
  Widget build(BuildContext context) {
    final kmText =
        '${dailyKm.toStringAsFixed(2)} / ${quest.thresholdKm.toStringAsFixed(1)} km';

    return Block(
      color: Rb.slot,
      edge: Rb.slateEdge,
      depth: 4,
      radius: 12,
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          // inventory slot icon
          Block(
            color: _color,
            edge: Rb.slateEdge,
            depth: 3,
            radius: 10,
            padding: EdgeInsets.zero,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: claimed
                    ? const Icon(Icons.check, color: Colors.white, size: 24)
                    : Icon(quest.icon, color: Colors.white, size: 24),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: BlockText(quest.title, size: 13, stroke: 3, maxLines: 1),
                    ),
                    const SizedBox(width: 6),
                    Block(
                      color: claimed ? Rb.silverEdge : Rb.blue,
                      edge: claimed ? Rb.slateEdge : Rb.blueEdge,
                      depth: 2,
                      radius: 6,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: BlockText(
                        claimed
                            ? '✓ ${quest.crystalReward} 💎'
                            : '+${quest.crystalReward} 💎',
                        size: 10,
                        stroke: 2.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  claimed ? 'Completed today!' : quest.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (!claimed) ...[
                  const SizedBox(height: 4),
                  Text(
                    kmText,
                    style: TextStyle(
                      color: _color,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                BlockBar(value: claimed ? 1 : progress, height: 12, color: _color),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Recent activity rows ─────────────────────────

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
          return const Block(
            color: Rb.slot,
            edge: Rb.slateEdge,
            depth: 4,
            radius: 12,
            padding: EdgeInsets.all(14),
            child: Text(
              'Activity history coming soon',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        }

        return Column(
          children: snapshot.data!.docs.map((doc) {
            final s = _parseSession(doc);
            final type = s['type'] as String;
            final color = _colorForType(type);
            return Block(
              color: Rb.slot,
              edge: Rb.slateEdge,
              depth: 4,
              radius: 12,
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Block(
                    color: color,
                    edge: Rb.slateEdge,
                    depth: 3,
                    radius: 10,
                    padding: EdgeInsets.zero,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: Text(_emojiForType(type), style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BlockText(type.toUpperCase(), size: 13, stroke: 3),
                        const SizedBox(height: 2),
                        Text(
                          '${(s['distanceKm'] as double).toStringAsFixed(2)} km  •  ${s['duration']}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  BlockText('+${s['xp']} XP', size: 12, stroke: 3, color: Rb.gold),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Map<String, dynamic> _parseSession(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final secs = (d['durationSeconds'] as num).toInt();
    return {
      'type': d['type'] as String? ?? 'run',
      'distanceKm': (d['distanceKm'] as num).toDouble(),
      'duration': '${secs ~/ 60}m ${secs % 60}s',
      'xp': (d['xpEarned'] as num).toInt(),
    };
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'walk': return Rb.green;
      case 'jog':  return Rb.blue;
      default:     return Rb.orange;
    }
  }

  String _emojiForType(String type) {
    switch (type) {
      case 'walk': return '🚶';
      case 'jog':  return '🏃';
      default:     return '🔥';
    }
  }
}
