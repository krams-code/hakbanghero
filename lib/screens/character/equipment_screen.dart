import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  equipment_screen.dart  —  HakbangHero  (Slayer Legends style)
// ══════════════════════════════════════════════════════════════════════════════

class EquipmentScreen extends StatefulWidget {
  const EquipmentScreen({super.key});

  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen>
    with SingleTickerProviderStateMixin {
  static const Color bgDeep   = Color(0xFF060C06);
  static const Color bgPanel  = Color(0xFF0A140A);
  static const Color bgCard   = Color(0xFF0F1E0F);
  static const Color green    = Color(0xFF00FF41);
  static const Color greenDim = Color(0xFF1A4A1A);
  static const Color gold     = Color(0xFFFFD700);
  static const Color purple   = Color(0xFF9B59FF);
  static const Color red      = Color(0xFFFF4444);
  static const Color teal     = Color(0xFF00E5CC);
  static const Color textMain = Color(0xFFE0F0E0);
  static const Color textSub  = Color(0xFF4A6A4A);

  static const Map<String, Color> rarityColor = {
    'Common'   : Color(0xFF9E9E9E),
    'Uncommon' : Color(0xFF4CAF50),
    'Rare'     : Color(0xFF2196F3),
    'Epic'     : Color(0xFF9C27B0),
    'Legendary': Color(0xFFFFD700),
    'Divine'   : Color(0xFFFF6B35),
  };

  static const List<Map<String, dynamic>> _slotDefs = [
    {'id': 'helm',    'label': 'HELM',    'icon': Icons.security,       'side': 'left'},
    {'id': 'weapon',  'label': 'WEAPON',  'icon': Icons.gavel,          'side': 'left'},
    {'id': 'gloves',  'label': 'GLOVES',  'icon': Icons.back_hand,      'side': 'left'},
    {'id': 'ring',    'label': 'RING',    'icon': Icons.circle_outlined, 'side': 'left'},
    {'id': 'chest',   'label': 'CHEST',   'icon': Icons.shield,         'side': 'right'},
    {'id': 'boots',   'label': 'BOOTS',   'icon': Icons.directions_run, 'side': 'right'},
    {'id': 'amulet',  'label': 'AMULET',  'icon': Icons.star_border,    'side': 'right'},
    {'id': 'offhand', 'label': 'OFF',     'icon': Icons.layers,         'side': 'right'},
  ];

  final Map<String, Map<String, dynamic>?> _equipped = {
    'helm'   : {'name': 'Shadow Crown',      'rarity': 'Epic',      'emoji': '👑', 'slot': 'helm',    'atk': 0,   'def': 210, 'spd': 0,   'hp': 800,  'xp': 10},
    'weapon' : {'name': 'Verdant Blade',     'rarity': 'Legendary', 'emoji': '⚔️', 'slot': 'weapon',  'atk': 480, 'def': 0,   'spd': 120, 'hp': 0,    'xp': 25},
    'gloves' : null,
    'ring'   : {'name': 'Arcane Ring',       'rarity': 'Rare',      'emoji': '💍', 'slot': 'ring',    'atk': 80,  'def': 40,  'spd': 0,   'hp': 300,  'xp': 5},
    'chest'  : {'name': 'Forest Plate',      'rarity': 'Rare',      'emoji': '🛡️', 'slot': 'chest',   'atk': 0,   'def': 340, 'spd': 0,   'hp': 1200, 'xp': 5},
    'boots'  : {'name': 'Windrunner Treads', 'rarity': 'Epic',      'emoji': '👟', 'slot': 'boots',   'atk': 0,   'def': 60,  'spd': 280, 'hp': 0,    'xp': 15},
    'amulet' : null,
    'offhand': null,
  };

  final List<Map<String, dynamic>?> _inventory = [
    {'name': 'Iron Sword',      'rarity': 'Common',   'emoji': '🗡️', 'slot': 'weapon',  'atk': 80,  'def': 0,   'spd': 10,  'hp': 0,   'xp': 0},
    {'name': 'Leather Hood',    'rarity': 'Common',   'emoji': '🪖', 'slot': 'helm',    'atk': 0,   'def': 60,  'spd': 0,   'hp': 200, 'xp': 0},
    {'name': 'Shadow Cloak',    'rarity': 'Uncommon', 'emoji': '🧥', 'slot': 'chest',   'atk': 0,   'def': 180, 'spd': 20,  'hp': 500, 'xp': 5},
    {'name': 'Storm Boots',     'rarity': 'Uncommon', 'emoji': '👟', 'slot': 'boots',   'atk': 0,   'def': 40,  'spd': 150, 'hp': 0,   'xp': 3},
    {'name': 'Phantom Blade',   'rarity': 'Epic',     'emoji': '⚔️', 'slot': 'weapon',  'atk': 380, 'def': 0,   'spd': 90,  'hp': 0,   'xp': 18},
    {'name': 'Divine Gauntlet', 'rarity': 'Divine',   'emoji': '🧤', 'slot': 'gloves',  'atk': 200, 'def': 200, 'spd': 50,  'hp': 600, 'xp': 30},
    null, null, null, null,
    null, null, null, null,
    null, null, null, null,
    null, null, null, null,
  ];

  String _selectedSlot = '';
  int    _filterIdx    = 0;
  late   TabController _tabCtrl;
  int    _manaCrystals = 0;
  bool   _loadingCurrency = true;

  static const _filterLabels = ['ALL', 'WEAPON', 'ARMOR', 'ACCESSORY'];

  int get _cp {
    int v = 1200;
    for (final e in _equipped.values) {
      if (e != null) {
        v += (e['atk'] as int) * 2;
        v += (e['def'] as int);
        v += ((e['spd'] as int) * 1.5).round();
        v += ((e['hp']  as int) * 0.3).round();
      }
    }
    return v;
  }

  int get _totalAtk => _equipped.values.fold(0, (s, e) => s + (e?['atk'] as int? ?? 0));
  int get _totalDef => _equipped.values.fold(0, (s, e) => s + (e?['def'] as int? ?? 0));
  int get _totalSpd => _equipped.values.fold(0, (s, e) => s + (e?['spd'] as int? ?? 0));
  int get _totalHp  => _equipped.values.fold(0, (s, e) => s + (e?['hp']  as int? ?? 0));

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _filterLabels.length, vsync: this)
      ..addListener(() => setState(() => _filterIdx = _tabCtrl.index));
    _loadCurrency();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrency() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loadingCurrency = false); return; }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (mounted) {
        setState(() {
          _manaCrystals    = (doc.data()?['gems'] as num?)?.toInt() ?? 0;
          _loadingCurrency = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCurrency = false);
    }
  }

  void _tapSlot(String slotId) {
    setState(() => _selectedSlot = (_selectedSlot == slotId) ? '' : slotId);
  }

  void _longPressSlot(String slotId) {
    final item = _equipped[slotId];
    if (item == null) return;
    final emptyIdx = _inventory.indexWhere((e) => e == null);
    if (emptyIdx == -1) { _snack('Inventory full!', red); return; }
    setState(() {
      _inventory[emptyIdx] = item;
      _equipped[slotId]    = null;
    });
  }

  void _tapInventory(int idx) {
    final item = _inventory[idx];
    if (item == null) return;

    if (_selectedSlot.isNotEmpty) {
      final compatSlot = item['slot'] as String;
      final target = (_selectedSlot == compatSlot) ? _selectedSlot : '';
      if (target.isEmpty) {
        _snack('Wrong slot! This is a ${item['slot'].toString().toUpperCase()}', red);
        return;
      }
      final old = _equipped[target];
      setState(() {
        _equipped[target]  = item;
        _inventory[idx]    = old;
        _selectedSlot      = '';
      });
    } else {
      _showDetail(item, idx);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content        : Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: color,
        duration       : const Duration(seconds: 2),
        behavior       : SnackBarBehavior.floating,
        shape          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showDetail(Map<String, dynamic> item, int invIdx) {
    final color = rarityColor[item['rarity']] ?? textSub;
    showModalBottomSheet(
      context            : context,
      backgroundColor    : Colors.transparent,
      isScrollControlled : true,
      builder: (_) => _ItemDetailSheet(
        item    : item,
        color   : color,
        onEquip : () {
          Navigator.pop(context);
          setState(() => _selectedSlot = item['slot'] as String);
          _snack('Tap the ${(item['slot'] as String).toUpperCase()} slot to equip', green);
        },
        onSell: () {
          Navigator.pop(context);
          setState(() => _inventory[invIdx] = null);
          _snack('Item sold for 50 gold', gold);
        },
      ),
    );
  }

  bool _passesFilter(Map<String, dynamic>? item) {
    if (item == null) return true;
    if (_filterIdx == 0) return true;
    final slot = (item['slot'] as String).toLowerCase();
    switch (_filterIdx) {
      case 1: return slot == 'weapon' || slot == 'offhand';
      case 2: return slot == 'helm' || slot == 'chest' || slot == 'boots' || slot == 'gloves';
      case 3: return slot == 'ring' || slot == 'amulet';
      default: return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDeep,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Column(
                children: [
                  _buildEquipZone(),
                  _buildCPBar(),
                  _buildStatRow(),
                  const SizedBox(height: 6),
                  Expanded(child: _buildInventory()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color : bgPanel,
        border: Border(bottom: BorderSide(color: green.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: green, width: 2), color: bgCard),
            child: const Icon(Icons.person, color: green, size: 20),
          ),
          const SizedBox(width: 8),
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(FirebaseAuth.instance.currentUser?.uid)
                .snapshots(),
            builder: (context, snapshot) {
              final username = (snapshot.data?.data() as Map<String, dynamic>?)?['username'] as String? ?? 'Hero';
              return Text(username,
                  style: const TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1));
            },
          ),
          const Spacer(),
          // Mana Crystals chip
          _GemChip(value: _loadingCurrency ? '...' : '$_manaCrystals'),
          const SizedBox(width: 10),
          const Icon(Icons.settings, color: textSub, size: 20),
        ],
      ),
    );
  }

  Widget _buildEquipZone() {
    final leftSlots  = _slotDefs.where((s) => s['side'] == 'left').toList();
    final rightSlots = _slotDefs.where((s) => s['side'] == 'right').toList();

    return Container(
      height: 236,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      decoration: BoxDecoration(
        color       : bgPanel,
        borderRadius: BorderRadius.circular(16),
        border      : Border.all(color: greenDim),
        boxShadow   : [BoxShadow(color: green.withValues(alpha: 0.04), blurRadius: 20)],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: leftSlots.map(_slotWidget).toList(),
            ),
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 140, height: 200,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(colors: [
                      green.withValues(alpha: 0.07),
                      Colors.transparent,
                    ]),
                  ),
                ),
                SizedBox(
                  width: 110, height: 200,
                  child: CustomPaint(painter: _HeroSpritePainter()),
                ),
                Positioned(
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color       : purple.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border      : Border.all(color: purple.withValues(alpha: 0.55)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt, color: purple, size: 13),
                        const SizedBox(width: 3),
                        Text('$_cp CP',
                            style: const TextStyle(color: purple, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                if (_selectedSlot.isNotEmpty)
                  Positioned(
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color       : green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border      : Border.all(color: green.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        'PICK ${_selectedSlot.toUpperCase()} FROM INVENTORY',
                        style: const TextStyle(color: green, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 74,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: rightSlots.map(_slotWidget).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slotWidget(Map<String, dynamic> def) {
    final id       = def['id']    as String;
    final label    = def['label'] as String;
    final iconData = def['icon']  as IconData;
    final item     = _equipped[id];
    final selected = _selectedSlot == id;
    final color    = item != null ? (rarityColor[item['rarity']] ?? green) : greenDim;

    return GestureDetector(
      onTap      : () => _tapSlot(id),
      onLongPress: () => _longPressSlot(id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 60, height: 50,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color       : selected ? color.withValues(alpha: 0.22) : bgCard,
          borderRadius: BorderRadius.circular(10),
          border      : Border.all(
            color: selected ? color : color.withValues(alpha: 0.45),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8)] : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            item != null
                ? Text(item['emoji'] as String, style: const TextStyle(fontSize: 20))
                : Icon(iconData, color: color, size: 18),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildCPBar() {
    return Container(
      margin : const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [const Color(0xFF1A0A3D), purple.withValues(alpha: 0.08)]),
        borderRadius: BorderRadius.circular(10),
        border      : Border.all(color: purple.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, color: purple, size: 16),
          const SizedBox(width: 6),
          const Text('COMBAT POWER', style: TextStyle(color: textSub, fontSize: 10, letterSpacing: 1.5)),
          const Spacer(),
          Text('$_cp', style: const TextStyle(color: purple, fontSize: 22, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildStatRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 0),
      child: Row(
        children: [
          _statBox('⚔️', 'ATK', '$_totalAtk', red),
          _statBox('🛡️', 'DEF', '$_totalDef', teal),
          _statBox('💨', 'SPD', '$_totalSpd', green),
          _statBox('❤️', 'HP',  '$_totalHp',  const Color(0xFFFF6B6B)),
        ],
      ),
    );
  }

  Widget _statBox(String emoji, String label, String val, Color color) => Expanded(
    child: Container(
      margin : const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color       : bgCard,
        borderRadius: BorderRadius.circular(8),
        border      : Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        children: [
          Text('$emoji $label', style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(val, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900)),
        ],
      ),
    ),
  );

  Widget _buildInventory() {
    final filled = _inventory.where((e) => e != null).length;
    return Container(
      margin : const EdgeInsets.fromLTRB(12, 7, 12, 12),
      decoration: BoxDecoration(
        color       : bgPanel,
        borderRadius: BorderRadius.circular(14),
        border      : Border.all(color: greenDim),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                const Text('INVENTORY',
                    style: TextStyle(color: green, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 2)),
                const SizedBox(width: 8),
                Text('$filled / ${_inventory.length} SLOTS',
                    style: const TextStyle(color: textSub, fontSize: 10)),
                const Spacer(),
                if (_selectedSlot.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color       : green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border      : Border.all(color: green.withValues(alpha: 0.4)),
                    ),
                    child: Text('SELECT ${_selectedSlot.toUpperCase()}',
                        style: const TextStyle(color: green, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: TabBar(
              controller          : _tabCtrl,
              indicatorColor      : green,
              labelColor          : green,
              unselectedLabelColor: textSub,
              indicatorSize       : TabBarIndicatorSize.label,
              labelStyle          : const TextStyle(fontWeight: FontWeight.bold, fontSize: 9, letterSpacing: 1),
              tabs: _filterLabels.map((t) => Tab(text: t)).toList(),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount  : 5,
                crossAxisSpacing: 8,
                mainAxisSpacing : 8,
                childAspectRatio: 0.85,
              ),
              itemCount  : _inventory.length,
              itemBuilder: (_, i) {
                final item = _inventory[i];
                if (item != null && !_passesFilter(item)) return _emptyCell();
                return _inventoryCell(i);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCell() => Container(
    decoration: BoxDecoration(
      color       : bgCard,
      borderRadius: BorderRadius.circular(8),
      border      : Border.all(color: greenDim.withValues(alpha: 0.3)),
    ),
  );

  Widget _inventoryCell(int i) {
    final item = _inventory[i];
    if (item == null) return _emptyCell();

    final color        = rarityColor[item['rarity']] ?? textSub;
    final isEquipped   = _equipped.values.any((e) => e != null && e['name'] == item['name']);
    final isCompatible = _selectedSlot.isNotEmpty && item['slot'] == _selectedSlot;

    return GestureDetector(
      onTap: () => _tapInventory(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        decoration: BoxDecoration(
          color       : isCompatible ? color.withValues(alpha: 0.22) : bgCard,
          borderRadius: BorderRadius.circular(8),
          border      : Border.all(
            color: isCompatible ? color : color.withValues(alpha: 0.45),
            width: isCompatible ? 2 : 1,
          ),
          boxShadow: isCompatible ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 6)] : [],
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(item['emoji'] as String, style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 3),
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                ],
              ),
            ),
            if (isEquipped)
              Positioned(
                top: 2, right: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(3)),
                  child: const Text('EQ', style: TextStyle(color: Colors.black, fontSize: 6, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Gem chip for header ───────────────────────────────────────────────────────
class _GemChip extends StatelessWidget {
  final String value;
  const _GemChip({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF7B4FFF).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF7B4FFF).withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: const Color(0xFF7B4FFF).withValues(alpha: 0.2), blurRadius: 8)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔮', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 5),
          Text(value,
              style: const TextStyle(color: Color(0xFFB388FF), fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Item Detail Bottom Sheet
// ══════════════════════════════════════════════════════════════════════════════
class _ItemDetailSheet extends StatelessWidget {
  final Map<String, dynamic> item;
  final Color color;
  final VoidCallback onEquip;
  final VoidCallback onSell;

  const _ItemDetailSheet({
    required this.item,
    required this.color,
    required this.onEquip,
    required this.onSell,
  });

  static const Color bgPanel  = Color(0xFF0A140A);
  static const Color bgCard   = Color(0xFF0F1E0F);
  static const Color textMain = Color(0xFFE0F0E0);
  static const Color textSub  = Color(0xFF4A6A4A);
  static const Color green    = Color(0xFF00FF41);
  static const Color red      = Color(0xFFFF4444);
  static const Color teal     = Color(0xFF00E5CC);
  static const Color gold     = Color(0xFFFFD700);
  static const Color purple   = Color(0xFF9B59FF);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color       : bgPanel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border      : Border(top: BorderSide(color: color, width: 1.5)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color       : color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border      : Border.all(color: color.withValues(alpha: 0.65), width: 1.5),
                  boxShadow   : [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 12)],
                ),
                child: Center(child: Text(item['emoji'] as String, style: const TextStyle(fontSize: 32))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['name'] as String,
                        style: const TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _badge(item['rarity'] as String, color),
                        const SizedBox(width: 6),
                        _badge((item['slot'] as String).toUpperCase(), textSub),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              if ((item['atk'] as int) > 0) _statPill('⚔️ ATK', '+${item['atk']}', red),
              if ((item['def'] as int) > 0) _statPill('🛡️ DEF', '+${item['def']}', teal),
              if ((item['spd'] as int) > 0) _statPill('💨 SPD', '+${item['spd']}', green),
              if ((item['hp']  as int) > 0) _statPill('❤️ HP',  '+${item['hp']}',  const Color(0xFFFF6B6B)),
              if ((item['xp']  as int) > 0) _statPill('✨ XP+', '+${item['xp']}%', purple),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onSell,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color       : bgCard,
                      borderRadius: BorderRadius.circular(12),
                      border      : Border.all(color: gold.withValues(alpha: 0.5)),
                    ),
                    child: const Text('SELL  🪙 50',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: gold, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: onEquip,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      gradient    : const LinearGradient(colors: [Color(0xFF00FF41), Color(0xFF00CC33)]),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow   : [BoxShadow(color: green.withValues(alpha: 0.3), blurRadius: 12)],
                    ),
                    child: const Text('EQUIP',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _badge(String label, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color       : c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
      border      : Border.all(color: c.withValues(alpha: 0.45)),
    ),
    child: Text(label, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold)),
  );

  Widget _statPill(String label, String val, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color       : c.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      border      : Border.all(color: c.withValues(alpha: 0.3)),
    ),
    child: Text('$label  $val', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  Hero Sprite Painter
// ══════════════════════════════════════════════════════════════════════════════
class _HeroSpritePainter extends CustomPainter {
  static const _green  = Color(0xFF00FF41);
  static const _darkBg = Color(0xFF0A1A0A);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;

    final fill       = Paint()..color = _darkBg..style = PaintingStyle.fill;
    final stroke     = Paint()..color = _green.withValues(alpha: 0.75)..style = PaintingStyle.stroke..strokeWidth = 1.6;
    final glow       = Paint()..color = _green.withValues(alpha: 0.12)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    final accentLine = Paint()..color = _green.withValues(alpha: 0.35)..strokeWidth = 0.9..style = PaintingStyle.stroke;

    final headCenter = Offset(cx, size.height * 0.11);
    canvas.drawCircle(headCenter, 14, glow);
    canvas.drawCircle(headCenter, 14, fill);
    canvas.drawCircle(headCenter, 14, stroke);

    final crest = Path()
      ..moveTo(cx - 6, size.height * 0.04)
      ..lineTo(cx,     size.height * 0.01)
      ..lineTo(cx + 6, size.height * 0.04);
    canvas.drawPath(crest, stroke);

    final shoulders = Path()
      ..moveTo(cx - 20, size.height * 0.25)
      ..quadraticBezierTo(cx - 32, size.height * 0.20, cx - 28, size.height * 0.30)
      ..lineTo(cx - 18, size.height * 0.33)
      ..lineTo(cx + 18, size.height * 0.33)
      ..lineTo(cx + 28, size.height * 0.30)
      ..quadraticBezierTo(cx + 32, size.height * 0.20, cx + 20, size.height * 0.25)
      ..lineTo(cx, size.height * 0.20)
      ..close();
    canvas.drawPath(shoulders, glow);
    canvas.drawPath(shoulders, fill);
    canvas.drawPath(shoulders, stroke);

    canvas.drawCircle(Offset(cx - 27, size.height * 0.24), 3, Paint()..color = _green.withValues(alpha: 0.5));
    canvas.drawCircle(Offset(cx + 27, size.height * 0.24), 3, Paint()..color = _green.withValues(alpha: 0.5));

    final torso = Path()
      ..moveTo(cx - 18, size.height * 0.33)
      ..lineTo(cx - 13, size.height * 0.56)
      ..lineTo(cx + 13, size.height * 0.56)
      ..lineTo(cx + 18, size.height * 0.33)
      ..close();
    canvas.drawPath(torso, fill);
    canvas.drawPath(torso, stroke);

    canvas.drawLine(Offset(cx, size.height * 0.34), Offset(cx, size.height * 0.55), accentLine);
    canvas.drawLine(Offset(cx - 9, size.height * 0.41), Offset(cx + 9, size.height * 0.41), accentLine);
    canvas.drawLine(Offset(cx - 8, size.height * 0.48), Offset(cx + 8, size.height * 0.48), accentLine);

    for (final side in [-1, 1]) {
      final sx = side.toDouble();
      final arm = Path()
        ..moveTo(cx + sx * 18, size.height * 0.33)
        ..quadraticBezierTo(cx + sx * 30, size.height * 0.44, cx + sx * 26, size.height * 0.59)
        ..lineTo(cx + sx * 19, size.height * 0.59)
        ..quadraticBezierTo(cx + sx * 22, size.height * 0.46, cx + sx * 13, size.height * 0.35)
        ..close();
      canvas.drawPath(arm, fill);
      canvas.drawPath(arm, stroke);
      canvas.drawCircle(Offset(cx + sx * 27, size.height * 0.46), 4,
          Paint()..color = _green.withValues(alpha: 0.3)..style = PaintingStyle.fill);
    }

    final belt = Rect.fromLTWH(cx - 13, size.height * 0.555, 26, 6);
    canvas.drawRect(belt, fill);
    canvas.drawRect(belt, stroke);
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, size.height * 0.558), width: 8, height: 6),
      Paint()..color = _green.withValues(alpha: 0.5)..style = PaintingStyle.fill,
    );

    for (final side in [-1, 1]) {
      final sx   = side.toDouble();
      final sign = side == -1 ? 0 : 1;
      final leg  = Path()
        ..moveTo(cx + sx * (sign == 0 ? -13 : 4),  size.height * 0.615)
        ..lineTo(cx + sx * (sign == 0 ? -16 : 7),  size.height * 0.79)
        ..lineTo(cx + sx * (sign == 0 ? -7  : 16), size.height * 0.79)
        ..lineTo(cx + sx * (sign == 0 ? -4  : 13), size.height * 0.615)
        ..close();
      canvas.drawPath(leg, fill);
      canvas.drawPath(leg, stroke);
      canvas.drawCircle(
        Offset(cx + sx * (sign == 0 ? -11 : 11), size.height * 0.70),
        4,
        Paint()..color = _green.withValues(alpha: 0.3)..style = PaintingStyle.fill,
      );
    }

    final lBoot = Path()
      ..moveTo(cx - 16, size.height * 0.79)
      ..lineTo(cx - 20, size.height * 0.90)
      ..lineTo(cx - 5,  size.height * 0.90)
      ..lineTo(cx - 7,  size.height * 0.79)
      ..close();
    canvas.drawPath(lBoot, fill);
    canvas.drawPath(lBoot, stroke);

    final rBoot = Path()
      ..moveTo(cx + 16, size.height * 0.79)
      ..lineTo(cx + 20, size.height * 0.90)
      ..lineTo(cx + 5,  size.height * 0.90)
      ..lineTo(cx + 7,  size.height * 0.79)
      ..close();
    canvas.drawPath(rBoot, fill);
    canvas.drawPath(rBoot, stroke);

    final eyePaint = Paint()
      ..color      = _green
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(Offset(cx - 5, size.height * 0.104), 2.5, eyePaint);
    canvas.drawCircle(Offset(cx + 5, size.height * 0.104), 2.5, eyePaint);
  }

  @override
  bool shouldRepaint(_HeroSpritePainter _) => false;
}