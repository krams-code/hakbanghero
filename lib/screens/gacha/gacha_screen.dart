import 'package:flutter/material.dart';

class GachaScreen extends StatefulWidget {
  const GachaScreen({super.key});

  @override
  State<GachaScreen> createState() => _GachaScreenState();
}

class _GachaScreenState extends State<GachaScreen>
    with TickerProviderStateMixin {
  // ── Palette ──────────────────────────────────────────────────────────────
  static const Color bgDeep    = Color(0xFF060C06);
  static const Color bgPanel   = Color(0xFF0A140A);
  static const Color bgCard    = Color(0xFF0F1E0F);
  static const Color green     = Color(0xFF00FF41);
  static const Color greenDim  = Color(0xFF1A4A1A);
  static const Color gold      = Color(0xFFFFD700);
  static const Color purple    = Color(0xFF9B59FF);
  static const Color teal      = Color(0xFF00E5CC);
  static const Color textMain  = Color(0xFFE0F0E0);
  static const Color textSub   = Color(0xFF4A6A4A);

  int _selectedTab = 1; // 0 = Heroes Guild, 1 = Ancient Artifacts
  bool _isPulling  = false;
  List<Map<String, dynamic>> _pullResults = [];

  late AnimationController _orbController;
  late AnimationController _pulseController;
  late Animation<double>   _orbRotation;
  late Animation<double>   _pulseScale;

  // ── Banner data ──────────────────────────────────────────────────────────
  static const List<Map<String, dynamic>> _banners = [
    {
      'id'       : 0,
      'name'     : 'HEROES GUILD',
      'subtitle' : 'Rare Hero Drop Rate 1%',
      'color'    : teal,
      'orbColor' : Color(0xFF00E5CC),
      'icon'     : '⚔️',
      'x1cost'   : 150,
      'x10cost'  : 1350,
      'currency' : 'souls',
      'currLabel': 'HEROIC SOULS',
    },
    {
      'id'       : 1,
      'name'     : 'ANCIENT ARTIFACTS',
      'subtitle' : 'Legendary Gear Drop Rate 0%',
      'color'    : gold,
      'orbColor' : Color(0xFFFFD700),
      'icon'     : '🔮',
      'x1cost'   : 150,
      'x10cost'  : 1350,
      'currency' : 'gems',
      'currLabel': 'ANCIENT ARTIFACTS',
    },
  ];

  // ── Loot table ───────────────────────────────────────────────────────────
  static const List<Map<String, dynamic>> _lootTable = [
    {'name': 'Iron Sword',      'rarity': 'Common',    'icon': '🗡️',  'type': 'Weapon',    'weight': 40},
    {'name': 'Leather Hood',    'rarity': 'Common',    'icon': '🪖',  'type': 'Helmet',    'weight': 35},
    {'name': 'Shadow Cloak',    'rarity': 'Uncommon',  'icon': '🧥',  'type': 'Armor',     'weight': 12},
    {'name': 'Storm Boots',     'rarity': 'Uncommon',  'icon': '👟',  'type': 'Boots',     'weight': 8},
    {'name': 'Arcane Ring',     'rarity': 'Rare',      'icon': '💍',  'type': 'Accessory', 'weight': 3},
    {'name': 'Phantom Blade',   'rarity': 'Epic',      'icon': '⚔️',  'type': 'Weapon',    'weight': 1},
    {'name': 'Verdant Blade',   'rarity': 'Legendary', 'icon': '🌿',  'type': 'Weapon',    'weight': 0},
    {'name': 'Divine Gauntlet', 'rarity': 'Divine',    'icon': '🧤',  'type': 'Gloves',    'weight': 0},
  ];

  static const Map<String, Color> rarityColor = {
    'Common'   : Color(0xFF9E9E9E),
    'Uncommon' : Color(0xFF4CAF50),
    'Rare'     : Color(0xFF2196F3),
    'Epic'     : Color(0xFF9C27B0),
    'Legendary': Color(0xFFFFD700),
    'Divine'   : Color(0xFFFF6B35),
  };

  @override
  void initState() {
    super.initState();

    _orbController = AnimationController(
      vsync  : this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _pulseController = AnimationController(
      vsync  : this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _orbRotation = Tween<double>(begin: 0, end: 1).animate(_orbController);
    _pulseScale  = Tween<double>(begin: 0.95, end: 1.05)
        .animate(CurvedAnimation(
            parent: _pulseController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _orbController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Pull logic ────────────────────────────────────────────────────────────
  Map<String, dynamic> _rollItem() {
    // Weighted random
    final totalWeight = _lootTable.fold<int>(
        0, (sum, item) => sum + (item['weight'] as int));
    int roll = (totalWeight * (DateTime.now().microsecondsSinceEpoch % 1000) /
            1000)
        .round();
    for (final item in _lootTable) {
      roll -= item['weight'] as int;
      if (roll <= 0) return item;
    }
    return _lootTable.first;
  }

  Future<void> _doPull(int count) async {
    if (_isPulling) return;
    setState(() {
      _isPulling   = true;
      _pullResults = [];
    });

    await Future.delayed(const Duration(milliseconds: 800));

    final results = List.generate(count, (_) => _rollItem());
    if (mounted) {
      setState(() {
        _pullResults = results;
        _isPulling   = false;
      });
      _showResultsSheet(results);
    }
  }

  void _showResultsSheet(List<Map<String, dynamic>> results) {
    showModalBottomSheet(
      context          : context,
      backgroundColor : Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PullResultsSheet(results: results, rarityColor: rarityColor),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final banner = _banners[_selectedTab];
    final accentColor = banner['color'] as Color;

    return Scaffold(
      backgroundColor: bgDeep,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(accentColor),
            _buildBannerTabs(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildOrbSection(banner, accentColor),
                    _buildBannerInfo(banner, accentColor),
                    const SizedBox(height: 16),
                    _buildPullButtons(banner, accentColor),
                    const SizedBox(height: 24),
                    _buildRateTable(accentColor),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color : bgPanel,
        border: Border(bottom: BorderSide(color: accent.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width : 36,
            height: 36,
            decoration: BoxDecoration(
              shape : BoxShape.circle,
              border: Border.all(color: green, width: 2),
              color : bgCard,
            ),
            child: const Icon(Icons.person, color: green, size: 20),
          ),
          const SizedBox(width: 8),
          const Text('HERO #4207',
              style: TextStyle(
                  color      : textMain,
                  fontWeight : FontWeight.bold,
                  fontSize   : 13,
                  letterSpacing: 1)),
          const Spacer(),
          // Currency chips
          _headerCurrencyChip('💎', '1,200', teal),
          const SizedBox(width: 6),
          _headerCurrencyChip('🔮', '350', gold),
          const SizedBox(width: 10),
          Icon(Icons.settings, color: textSub, size: 20),
        ],
      ),
    );
  }

  Widget _headerCurrencyChip(String icon, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color       : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border      : Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(val,
              style: TextStyle(
                  color     : color,
                  fontWeight: FontWeight.bold,
                  fontSize  : 12)),
        ],
      ),
    );
  }

  // ── Banner tabs ───────────────────────────────────────────────────────────
  Widget _buildBannerTabs() {
    return Container(
      margin : const EdgeInsets.all(16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color       : bgCard,
        borderRadius: BorderRadius.circular(12),
        border      : Border.all(color: greenDim),
      ),
      child: Row(
        children: List.generate(_banners.length, (i) {
          final b        = _banners[i];
          final selected = _selectedTab == i;
          final color    = b['color'] as Color;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color       : selected ? color.withValues(alpha: 0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border      : selected
                      ? Border.all(color: color.withValues(alpha: 0.6))
                      : null,
                ),
                child: Text(
                  b['name'] as String,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color      : selected ? color : textSub,
                      fontWeight : FontWeight.bold,
                      fontSize   : 11,
                      letterSpacing: 1),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Orb / Summon Circle ───────────────────────────────────────────────────
  Widget _buildOrbSection(Map<String, dynamic> banner, Color accent) {
    return SizedBox(
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer rotating ring
          AnimatedBuilder(
            animation: _orbRotation,
            builder: (_, __) => Transform.rotate(
              angle: _orbRotation.value * 6.28,
              child: Container(
                width : 220,
                height: 220,
                decoration: BoxDecoration(
                  shape  : BoxShape.circle,
                  border : Border.all(
                      color: accent.withValues(alpha: 0.15), width: 1),
                ),
                child: CustomPaint(
                  painter: _DashCirclePainter(color: accent),
                ),
              ),
            ),
          ),
          // Inner glow ring
          AnimatedBuilder(
            animation: _pulseScale,
            builder: (_, __) => Transform.scale(
              scale: _pulseScale.value,
              child: Container(
                width : 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withValues(alpha: 0.25),
                      accent.withValues(alpha: 0.05),
                      Colors.transparent,
                    ],
                  ),
                  border: Border.all(
                      color: accent.withValues(alpha: 0.6), width: 2),
                  boxShadow: [
                    BoxShadow(
                        color    : accent.withValues(alpha: 0.3),
                        blurRadius: 30,
                        spreadRadius: 5),
                  ],
                ),
              ),
            ),
          ),
          // Center icon
          Text(banner['icon'] as String,
              style: const TextStyle(fontSize: 52)),

          if (_isPulling)
            Container(
              width : 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.6),
              ),
              child: const Center(
                child: CircularProgressIndicator(color: green, strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  // ── Banner info strip ─────────────────────────────────────────────────────
  Widget _buildBannerInfo(Map<String, dynamic> banner, Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Text(
            '${banner['name']} SUMMON',
            style: TextStyle(
                color      : accent,
                fontSize   : 18,
                fontWeight : FontWeight.w900,
                letterSpacing: 2),
          ),
          const SizedBox(height: 4),
          Text(
            banner['subtitle'] as String,
            style: TextStyle(
                color  : accent.withValues(alpha: 0.7),
                fontSize: 11,
                letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  // ── Pull buttons ──────────────────────────────────────────────────────────
  Widget _buildPullButtons(Map<String, dynamic> banner, Color accent) {
    final currLabel = banner['currLabel'] as String;
    final x1cost    = banner['x1cost']   as int;
    final x10cost   = banner['x10cost']  as int;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _pullButton(
            label   : 'EQUIPMENT X1',
            cost    : '$x1cost',
            currency: currLabel,
            accent  : accent,
            onTap   : () => _doPull(1),
          ),
          const SizedBox(width: 12),
          _pullButton(
            label   : 'EQUIPMENT X10',
            cost    : '$x10cost',
            currency: currLabel,
            accent  : gold,
            tag     : 'BEST',
            onTap   : () => _doPull(10),
          ),
        ],
      ),
    );
  }

  Widget _pullButton({
    required String label,
    required String cost,
    required String currency,
    required Color accent,
    required VoidCallback onTap,
    String? tag,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: _isPulling ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color       : bgCard,
            borderRadius: BorderRadius.circular(14),
            border      : Border.all(color: accent.withValues(alpha: 0.5)),
            boxShadow   : [
              BoxShadow(
                  color    : accent.withValues(alpha: 0.1),
                  blurRadius: 10),
            ],
          ),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              Column(
                children: [
                  Text(label,
                      style: TextStyle(
                          color      : accent,
                          fontSize   : 11,
                          fontWeight : FontWeight.bold,
                          letterSpacing: 1)),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('🔮 ',
                          style: const TextStyle(fontSize: 14)),
                      Text(cost,
                          style: TextStyle(
                              color     : accent,
                              fontSize  : 20,
                              fontWeight: FontWeight.w900)),
                    ],
                  ),
                  Text(currency,
                      style: const TextStyle(
                          color  : textSub,
                          fontSize: 9,
                          letterSpacing: 0.5)),
                ],
              ),
              if (tag != null)
                Positioned(
                  top  : -4,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color       : gold,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(tag,
                        style: const TextStyle(
                            color     : Colors.black,
                            fontSize  : 8,
                            fontWeight: FontWeight.w900)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Rate table ────────────────────────────────────────────────────────────
  Widget _buildRateTable(Color accent) {
    final rates = [
      ('Common',    '75%', rarityColor['Common']!),
      ('Uncommon',  '20%', rarityColor['Uncommon']!),
      ('Rare',       '3%', rarityColor['Rare']!),
      ('Epic',       '1%', rarityColor['Epic']!),
      ('Legendary', '0.9%', rarityColor['Legendary']!),
      ('Divine',    '0.1%', rarityColor['Divine']!),
    ];

    return Container(
      margin : const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color       : bgCard,
        borderRadius: BorderRadius.circular(14),
        border      : Border.all(color: greenDim),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: accent, size: 14),
              const SizedBox(width: 6),
              Text('DROP RATES',
                  style: TextStyle(
                      color      : accent,
                      fontSize   : 11,
                      fontWeight : FontWeight.bold,
                      letterSpacing: 2)),
            ],
          ),
          const SizedBox(height: 12),
          ...rates.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width : 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: r.$3, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(r.$1,
                        style: TextStyle(
                            color  : r.$3,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(r.$2,
                        style: const TextStyle(
                            color  : textMain,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ── Pull Results Bottom Sheet ─────────────────────────────────────────────────
class _PullResultsSheet extends StatelessWidget {
  final List<Map<String, dynamic>> results;
  final Map<String, Color> rarityColor;

  const _PullResultsSheet(
      {required this.results, required this.rarityColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color       : Color(0xFF0A140A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border      : Border(
            top: BorderSide(color: Color(0xFF00FF41), width: 1)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width : 40,
            height: 4,
            decoration: BoxDecoration(
              color       : const Color(0xFF1A4A1A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text('SUMMON RESULTS',
              style: TextStyle(
                  color      : Color(0xFF00FF41),
                  fontWeight : FontWeight.bold,
                  fontSize   : 14,
                  letterSpacing: 3)),
          const SizedBox(height: 16),
          Wrap(
            spacing   : 10,
            runSpacing: 10,
            alignment : WrapAlignment.center,
            children  : results.map((item) {
              final color = rarityColor[item['rarity']] ??
                  const Color(0xFF9E9E9E);
              return Container(
                width  : 80,
                height : 90,
                decoration: BoxDecoration(
                  color       : color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border      : Border.all(
                      color: color.withValues(alpha: 0.7), width: 2),
                  boxShadow: [
                    BoxShadow(
                        color    : color.withValues(alpha: 0.2),
                        blurRadius: 8),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(item['icon'] as String,
                        style: const TextStyle(fontSize: 28)),
                    const SizedBox(height: 4),
                    Text(
                      item['rarity'] as String,
                      style: TextStyle(
                          color    : color,
                          fontSize : 8,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      item['name'] as String,
                      style: const TextStyle(
                          color  : Color(0xFFE0F0E0),
                          fontSize: 8),
                      textAlign: TextAlign.center,
                      maxLines : 2,
                      overflow : TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width  : double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color       : const Color(0xFF1A4A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF00FF41), width: 1),
              ),
              child: const Text('CLOSE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color      : Color(0xFF00FF41),
                      fontWeight : FontWeight.bold,
                      letterSpacing: 2)),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Dashed Circle Painter ─────────────────────────────────────────────────────
class _DashCirclePainter extends CustomPainter {
  final Color color;
  const _DashCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = color.withValues(alpha: 0.4)
      ..strokeWidth = 1.5
      ..style       = PaintingStyle.stroke;

    const dashes = 24;
    const dashLen = 0.15;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = (size.width / 2) - 2;

    for (int i = 0; i < dashes; i++) {
      final startAngle = (i * 2 * 3.14159) / dashes;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        startAngle,
        dashLen,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashCirclePainter old) => old.color != color;
}
