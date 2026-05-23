import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _portalController;
  late AnimationController _pulseController;
  late AnimationController _entryController;
  late Animation<double> _portalRotation;
  late Animation<double> _portalGlow;
  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;

  Map<String, dynamic>? _userData;
  bool _loadingUser = true;

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

    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (mounted && doc.exists) {
        setState(() {
          _userData = doc.data();
          _loadingUser = false;
        });
      } else {
        setState(() => _loadingUser = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingUser = false);
    }
  }

  @override
  void dispose() {
    _portalController.dispose();
    _pulseController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  String get _username =>
      _userData?['username'] as String? ??
      FirebaseAuth.instance.currentUser?.displayName ??
      'Hero';
  int get _level => (_userData?['level'] as num?)?.toInt() ?? 1;
  int get _xp => (_userData?['xp'] as num?)?.toInt() ?? 0;
  int get _coins => (_userData?['coins'] as num?)?.toInt() ?? 0;
  int get _gems => (_userData?['gems'] as num?)?.toInt() ?? 0;
  int get _heroicSouls => (_userData?['heroic_souls'] as num?)?.toInt() ?? 0;
  double get _totalKm => (_userData?['total_km'] as num?)?.toDouble() ?? 0.0;
  int get _totalSessions =>
      (_userData?['total_sessions'] as num?)?.toInt() ?? 0;

  int get _xpForNextLevel => _level * 500;
  double get _xpProgress =>
      (_xp % _xpForNextLevel) / _xpForNextLevel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060C06),
      body: _loadingUser
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00FF41)))
          : FadeTransition(
              opacity: _entryFade,
              child: SlideTransition(
                position: _entrySlide,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildTopBar()),
                    SliverToBoxAdapter(child: _buildXPBar()),
                    SliverToBoxAdapter(child: _buildStatsRow()),
                    SliverToBoxAdapter(child: _buildPortalSection()),
                    SliverToBoxAdapter(child: _buildActiveQuests()),
                    SliverToBoxAdapter(child: _buildRecentActivity()),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 16,
        right: 16,
        bottom: 12,
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
          // Hero avatar + name
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
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
                    _username,
                    style: const TextStyle(
                      color: Color(0xFFE8FFE8),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00FF41).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: const Color(0xFF00FF41).withOpacity(0.4)),
                        ),
                        child: Text(
                          'LVL $_level',
                          style: const TextStyle(
                            color: Color(0xFF00FF41),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'HERO',
                        style: TextStyle(
                          color: const Color(0xFF4A8A4A),
                          fontSize: 10,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          // Currency chips
          _CurrencyChip(
              icon: Icons.monetization_on,
              value: _coins,
              color: const Color(0xFFFFD700)),
          const SizedBox(width: 8),
          _CurrencyChip(
              icon: Icons.diamond,
              value: _gems,
              color: const Color(0xFF00CFFF)),
          const SizedBox(width: 8),
          _CurrencyChip(
              icon: Icons.whatshot,
              value: _heroicSouls,
              color: const Color(0xFFFF6B35)),
        ],
      ),
    );
  }

  Widget _buildXPBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'EXP  $_xp / $_xpForNextLevel',
                style: const TextStyle(
                  color: Color(0xFF4A8A4A),
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                '${(_xpProgress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Color(0xFF00FF41),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
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
              widthFactor: _xpProgress.clamp(0.0, 1.0),
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

  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          _StatCard(
            label: 'TOTAL KM',
            value: _totalKm.toStringAsFixed(1),
            unit: 'km',
            icon: Icons.route,
            color: const Color(0xFF00FF41),
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: 'SESSIONS',
            value: '$_totalSessions',
            unit: 'runs',
            icon: Icons.flag,
            color: const Color(0xFF00CFFF),
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: 'STAGE',
            value: '1-3',
            unit: 'dungeon',
            icon: Icons.castle,
            color: const Color(0xFFFFD700),
          ),
        ],
      ),
    );
  }

  Widget _buildPortalSection() {
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
                  color: Color(0xFF4A8A4A),
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: const Color(0xFFFFD700).withOpacity(0.3)),
                ),
                child: const Text(
                  'STAGE 1-3',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () {}, // Navigate to stages
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF1A4A1A),
                  width: 1.5,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // Dark bg
                  Container(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.8,
                        colors: [
                          Color(0xFF0D2A1A),
                          Color(0xFF060C06),
                        ],
                      ),
                    ),
                  ),
                  // Grid lines
                  CustomPaint(
                    size: Size.infinite,
                    painter: _GridPainter(),
                  ),
                  // Portal glow rings
                  AnimatedBuilder(
                    animation: _portalGlow,
                    builder: (_, __) => Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer glow
                          Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6600CC)
                                      .withOpacity(0.15 * _portalGlow.value),
                                  blurRadius: 40,
                                  spreadRadius: 20,
                                ),
                              ],
                            ),
                          ),
                          // Rotating ring
                          AnimatedBuilder(
                            animation: _portalRotation,
                            builder: (_, __) => Transform.rotate(
                              angle: _portalRotation.value * 2 * 3.14159,
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF6600CC)
                                        .withOpacity(0.6),
                                    width: 2,
                                  ),
                                ),
                                child: CustomPaint(
                                    painter: _DashedCirclePainter()),
                              ),
                            ),
                          ),
                          // Inner portal
                          Container(
                            width: 90,
                            height: 90,
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
                                  blurRadius: 20,
                                  spreadRadius: 5,
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
                  // Bottom label
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Column(
                      children: [
                        const Text(
                          'THE HAUNTED HIGHLANDS',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFCC88FF),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Reach 5.0 km to unlock next stage',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: const Color(0xFF4A8A4A),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Tap overlay hint
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'TAP TO ENTER',
                        style: TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 9,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // START RUN button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
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
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Container(
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.directions_run,
                          color: Color(0xFF0A0F0A), size: 22),
                      SizedBox(width: 10),
                      Text(
                        'START RUN',
                        style: TextStyle(
                          color: Color(0xFF0A0F0A),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3,
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

  Widget _buildActiveQuests() {
    final quests = [
      _QuestData(
          title: 'Morning Runner',
          desc: 'Run 3km before 9 AM',
          progress: 0.6,
          reward: '50 coins',
          icon: Icons.wb_sunny),
      _QuestData(
          title: 'Step Master',
          desc: 'Reach 10,000 steps today',
          progress: 0.35,
          reward: '1 gem',
          icon: Icons.transfer_within_a_station),
      _QuestData(
          title: 'Weekly Warrior',
          desc: 'Complete 5 sessions this week',
          progress: 0.8,
          reward: '5 souls',
          icon: Icons.local_fire_department),
    ];

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
                  color: Color(0xFF4A8A4A),
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: const Color(0xFFFF6B35).withOpacity(0.4)),
                ),
                child: Text(
                  '${quests.length} ACTIVE',
                  style: const TextStyle(
                    color: Color(0xFFFF6B35),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...quests.map((q) => _QuestCard(quest: q)).toList(),
        ],
      ),
    );
  }

  Widget _buildRecentActivity() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RECENT ACTIVITY',
            style: TextStyle(
              color: Color(0xFF4A8A4A),
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (_totalSessions == 0)
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
                    Icon(Icons.directions_run,
                        color: Color(0xFF2A4A2A), size: 32),
                    SizedBox(height: 8),
                    Text(
                      'No runs yet — start your first session!',
                      style:
                          TextStyle(color: Color(0xFF3A6A3A), fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
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
            ),
        ],
      ),
    );
  }
}

// ─── Sub-widgets ────────────────────────────────────────────────────────────

class _CurrencyChip extends StatelessWidget {
  final IconData icon;
  final int value;
  final Color color;

  const _CurrencyChip(
      {required this.icon, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
          Text(
            value > 9999 ? '${(value / 1000).toStringAsFixed(1)}k' : '$value',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

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
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              unit,
              style: const TextStyle(
                color: Color(0xFF3A5A3A),
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF3A6A3A),
                fontSize: 9,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestData {
  final String title;
  final String desc;
  final double progress;
  final String reward;
  final IconData icon;

  const _QuestData({
    required this.title,
    required this.desc,
    required this.progress,
    required this.reward,
    required this.icon,
  });
}

class _QuestCard extends StatelessWidget {
  final _QuestData quest;

  const _QuestCard({required this.quest});

  Color get _progressColor {
    if (quest.progress >= 0.8) return const Color(0xFF00FF41);
    if (quest.progress >= 0.5) return const Color(0xFFFFD700);
    return const Color(0xFFFF6B35);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A0D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1A3A1A)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _progressColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: _progressColor.withOpacity(0.3)),
            ),
            child: Icon(quest.icon, color: _progressColor, size: 18),
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
                      style: const TextStyle(
                        color: Color(0xFFD0EED0),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        quest.reward,
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  quest.desc,
                  style: const TextStyle(
                    color: Color(0xFF4A7A4A),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
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
                      widthFactor: quest.progress,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: _progressColor,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
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

// ─── Custom Painters ────────────────────────────────────────────────────────

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

    const dashCount = 16;
    const gapFraction = 0.4;
    const pi2 = 2 * 3.14159265;
    final r = size.width / 2;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final dashLen = pi2 / dashCount * (1 - gapFraction);
    final gapLen = pi2 / dashCount * gapFraction;

    double angle = 0;
    for (int i = 0; i < dashCount; i++) {
      final start = angle;
      final end = angle + dashLen;
      final path = Path();
      path.addArc(
          Rect.fromCircle(center: Offset(cx, cy), radius: r), start, end - start);
      canvas.drawPath(path, paint);
      angle += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(_) => false;
}