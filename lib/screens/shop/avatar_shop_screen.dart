import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/asset_paths.dart';
import '../../models/character_profile.dart';
import '../../models/outfit_catalog.dart';
import '../../widgets/avatar_layer_stack.dart' show kSpriteWidth, kSpriteHeight;
import '../../widgets/avatar_preview.dart';
import '../../utils/player_stats.dart' show LevelProgress;
import '../../constants/app_icons.dart';
import '../../utils/activity_snapshot.dart';
import '../../utils/weekly.dart';
import '../../widgets/block_ui.dart';
import '../../widgets/pixel_icon.dart';

// ═════════════════════════════════════════════════════════════════
//  Avatar Item Shop — direct purchase (replaces the gacha screen)
//
//  Firestore (users/{uid}) fields used:
//    gems            int      currency
//    total_km        double   milestone unlocks
//    owned_items     [String] bought item ids
//    hair_style / face_expression / equipped_clothes / background_id
//                             saved look
//
//  LOCKING (see isShopItemUnlocked):
//    free item          price 0, no km gate  -> always unlocked (starter pack)
//    premium item       price > 0            -> unlocked only AFTER it is bought:
//                                               gems are subtracted in a
//                                               transaction, then the id is
//                                               added to owned_items
//    milestone item     unlockKm > 0, price 0-> unlocked automatically once
//                                               total_km reaches unlockKm
//    XP milestone item  unlockLevel > 1, price 0 -> unlocked automatically once
//                                               the hero reaches that level
//    premium + km gate  both must be satisfied
// ═════════════════════════════════════════════════════════════════

// ───────────────────────── Catalog ─────────────────────────

enum ShopCategory { hair, colors, clothes, faces, backgrounds }

class ShopItem {
  final String id;          // must match HairStyle / FaceExpression / clothes / background ids
  final ShopCategory category;
  final String name;
  final int price;          // gems; 0 = free
  final double unlockKm;    // > 0 = locked until this many total km
  final int unlockLevel;    // > 1 = locked until the hero reaches this XP level
  final String? asset;      // PNG key (hair / clothes / faces)
  final String emoji;       // fallback icon when there's no art yet
  final String? colorHex;   // hair-colour items: '#RRGGBB'
  final String? slot;       // Gear slot: weapon | armor | boots | ring

  const ShopItem({
    required this.id,
    required this.category,
    required this.name,
    this.price = 0,
    this.unlockKm = 0,
    this.unlockLevel = 0,
    this.asset,
    this.emoji = '📦',
    this.colorHex,
    this.slot,
  });

  /// Free and not milestone-gated = everyone owns it from the start.
  bool get isFree => price == 0 && unlockKm == 0 && unlockLevel <= 1;

  /// Short reason shown on locks (km gate and/or level gate).
  String lockLabel(double totalKm, int level) {
    if (unlockLevel > level) return 'Reach LV $unlockLevel to Unlock';
    return 'Run ${unlockKm.toStringAsFixed(1)} Total KM to Unlock';
  }

  /// Can be shown on the avatar (has art, or is a background).
  bool get equippable =>
      category == ShopCategory.backgrounds ||
      category == ShopCategory.colors ||
      asset != null;
}

/// The single source of truth for "can this player use [item] right now?".
/// The shop AND the gear chest both call it, so they can never disagree.
bool isShopItemUnlocked(
  ShopItem item, {
  required Set<String> owned,
  required double totalKm,
  int level = 1,
}) {
  if (item.isFree) return true; // starter pack
  if (item.unlockLevel > level) return false; // XP milestone not reached yet
  if (item.unlockKm > totalKm) return false; // milestone not reached yet
  if (item.price == 0) return true; // pure milestone reward: auto-unlocks
  return owned.contains(item.id); // premium: only after the purchase
}

/// Only items whose art really exists in assets/. Add a line to add an item.
const List<ShopItem> kShopCatalog = [
  // 💇 HAIR (ids = HairStyle ids)
  ShopItem(id: 'short_crop', category: ShopCategory.hair, name: 'Short Crop',
      asset: '$kHairDir/hair_14_short_crop.png', emoji: '💇'),
  ShopItem(id: 'warrior_spiky', category: ShopCategory.hair, name: 'Warrior Spiky',
      unlockLevel: 2, asset: '$kHairDir/hair_01_warrior_spiky.png', emoji: '💇'),
  ShopItem(id: 'classic_pompadour', category: ShopCategory.hair, name: 'Pompadour',
      price: 150, asset: '$kHairDir/hair_03_classic_pompadour.png', emoji: '💇'),
  // ⭐ starter hair (free for every new hero, see StarterPack)
  ShopItem(id: 'wavy_mane', category: ShopCategory.hair, name: 'Wavy Mane',
      asset: '$kHairDir/hair_05_wavy_mane.png', emoji: '💇'),
  ShopItem(id: 'long_flowing', category: ShopCategory.hair, name: 'Long & Flowing',
      price: 250, unlockKm: 25, asset: '$kHairDir/hair_07_long_flowing.png', emoji: '💇'),

  // 🎨 HAIR COLOURS (tint over any hair style)
  ShopItem(id: 'hc_1A1A1A', category: ShopCategory.colors, name: 'Jet Black',
      colorHex: '#1A1A1A', emoji: '🎨'),
  ShopItem(id: 'hc_3B2415', category: ShopCategory.colors, name: 'Espresso',
      colorHex: '#3B2415', emoji: '🎨'),
  ShopItem(id: 'hc_8B5A2B', category: ShopCategory.colors, name: 'Chestnut',
      price: 60, colorHex: '#8B5A2B', emoji: '🎨'),
  ShopItem(id: 'hc_4A4A4A', category: ShopCategory.colors, name: 'Ash Gray',
      price: 60, colorHex: '#4A4A4A', emoji: '🎨'),
  ShopItem(id: 'hc_D2A679', category: ShopCategory.colors, name: 'Sandy',
      price: 80, colorHex: '#D2A679', emoji: '🎨'),
  // Black, Espresso (brown) and Golden Blonde are the free starter colours
  ShopItem(id: 'hc_E8C468', category: ShopCategory.colors, name: 'Golden Blonde',
      colorHex: '#E8C468', emoji: '🎨'),
  ShopItem(id: 'hc_B33A1E', category: ShopCategory.colors, name: 'Legendary Crimson',
      price: 200, colorHex: '#B33A1E', emoji: '🎨'),

  // 🎽 CLOTHES
  // ⭐ starter outfit: the white tank-top set (free). Female heroes get the
  // body-matched file female/clothes/starter_set_<bodyType>.png.
  ShopItem(id: kStarterOutfitId, category: ShopCategory.clothes, name: 'Training Set',
      asset: '$kClothesDir/outfit_01.png', emoji: '🎽', slot: 'armor'),
  // Milestone reward with no art yet (shows as locked / "art coming soon")
  ShopItem(id: 'slayer_boots', category: ShopCategory.clothes, name: 'Slayer Iron Boots',
      unlockKm: 15, emoji: '🥾', slot: 'boots'),

  // 🎭 FACES
  ShopItem(id: 'neutral', category: ShopCategory.faces, name: 'Neutral',
      asset: '$kFaceDir/expression_01.png', emoji: '🎭'),

  // 🌌 BACKGROUNDS (ids = BlockBackground ids)
  ShopItem(id: 'valley', category: ShopCategory.backgrounds, name: 'Verdant Vale', emoji: '🌳'),
  ShopItem(id: 'boss_map', category: ShopCategory.backgrounds, name: 'Hero Trail',
      price: 100, emoji: '🗺️'),
  ShopItem(id: 'ashen', category: ShopCategory.backgrounds, name: 'Ashen Peaks',
      price: 150, emoji: '🌋'),
  ShopItem(id: 'frozen', category: ShopCategory.backgrounds, name: 'Frozen Tundra',
      price: 200, unlockKm: 35, emoji: '❄️'),
];

const List<(ShopCategory, String, String)> _cats = [
  (ShopCategory.hair, '💇', 'HAIR'),
  (ShopCategory.colors, '🎨', 'COLORS'),
  (ShopCategory.clothes, '🎽', 'CLOTHES'),
  (ShopCategory.faces, '🎭', 'FACES'),
  (ShopCategory.backgrounds, '🌌', 'BACKGROUNDS'),
];

// ───────────────────────── Saved data ─────────────────────────

class _ShopData {
  final int gems;
  final double totalKm;
  final int level;
  final int xp;
  final Set<String> owned;
  final Set<String> streakClaims;
  final String hair, face, clothes, bg;
  final String bodyId, skinTone, hairColor;
  final String? gender;

  const _ShopData({
    required this.gems,
    required this.totalKm,
    required this.level,
    required this.xp,
    required this.owned,
    required this.streakClaims,
    required this.hair,
    required this.face,
    required this.clothes,
    required this.bg,
    required this.bodyId,
    required this.skinTone,
    required this.hairColor,
    required this.gender,
  });

  factory _ShopData.from(Map<String, dynamic> d) {
    final p = CharacterProfile.fromFirestore(d);
    final stored = d['body_tier'] as String?;
    final tier = (p.heightCm == null || p.weightKg == null) && stored != null
        ? BodyTierExt.fromId(stored)
        : p.bodyTier;

    final rawClothes = d['equipped_clothes'];
    final clothesList = rawClothes is List ? rawClothes.whereType<String>().toList() : null;
    final clothes = clothesList == null
        ? StarterPack.activeOutfit
        : (clothesList.isEmpty ? '' : normalizeOutfitId(clothesList.first));

    final ownedRaw = d['owned_items'];

    return _ShopData(
      gems: (d['gems'] as num?)?.toInt() ?? 0,
      totalKm: (d['total_km'] as num?)?.toDouble() ?? 0.0,
      level: LevelProgress.fromXp((d['xp'] as num?)?.toInt() ?? 0).level,
      xp: (d['xp'] as num?)?.toInt() ?? 0,
      owned: ownedRaw is List ? ownedRaw.whereType<String>().toSet() : <String>{},
      streakClaims: d['streak_claims'] is List
          ? (d['streak_claims'] as List).whereType<String>().toSet()
          : <String>{},
      hair: p.hairStyle.id,
      face: p.faceExpression.id,
      clothes: clothes,
      bg: (d['background_id'] as String?) ?? 'valley',
      bodyId: tier.id,
      skinTone: p.skinTone,
      hairColor: p.hairColor,
      gender: p.gender,
    );
  }
}

// ───────────────────────── Screen ─────────────────────────

class AvatarShopScreen extends StatefulWidget {
  const AvatarShopScreen({super.key});

  @override
  State<AvatarShopScreen> createState() => _AvatarShopScreenState();
}

class _AvatarShopScreenState extends State<AvatarShopScreen> {
  ShopCategory? _cat; // null = FEATURED tab
  String _query = '';
  final TextEditingController _searchCtl = TextEditingController();
  ActivitySnapshot _act = const ActivitySnapshot();
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      ActivitySnapshot.load(uid).then((a) {
        if (mounted) setState(() => _act = a);
      });
    }
  }

  // ── weekly pick + streak rewards ──

  /// Streak milestones: days -> gem reward.
  static const List<(int, int)> _streakRewards = [(3, 25), (7, 75), (14, 150), (30, 400)];

  String _streakKey(int days) {
    final st = _act.streakStart;
    if (st == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '$days:${st.year}-${two(st.month)}-${two(st.day)}';
  }

  /// One purchasable item is spotlighted per week (same for every player).
  ShopItem? _weeklyPick() {
    final pool = kShopCatalog
        .where((i) =>
            i.price > 0 && i.unlockKm == 0 && i.unlockLevel <= 1 && i.equippable)
        .toList();
    if (pool.isEmpty) return null;
    return pool[Weekly.index(DateTime.now()) % pool.length];
  }

  Future<void> _claimStreak(String uid, int days, int gems) async {
    final key = _streakKey(days);
    if (key.isEmpty || _claiming) return;
    setState(() => _claiming = true);
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final snap = await txn.get(ref);
        final done = (snap.data()?['streak_claims'] as List?)?.contains(key) ?? false;
        if (done) throw 'claimed';
        txn.update(ref, {
          'gems': FieldValue.increment(gems),
          'streak_claims': FieldValue.arrayUnion([key]),
        });
      });
      _snack('🔥 $days-day streak reward: +$gems 💎');
    } catch (e) {
      _snack(e == 'claimed' ? 'Already claimed.' : 'Claim failed. Try again.');
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  // Draft look = what the live preview shows (not saved until purchase).
  String _sig = '';
  String _hair = '', _face = '', _clothes = '', _bg = '', _hairColor = '';

  bool _buying = false;

  // ── helpers ──

  ShopItem? _find(ShopCategory c, String id) {
    for (final i in kShopCatalog) {
      if (i.category != c) continue;
      if (c == ShopCategory.colors) {
        if (i.colorHex?.toUpperCase() == id.toUpperCase()) return i;
      } else if (i.id == id) {
        return i;
      }
    }
    return null;
  }

  String _draftOf(ShopCategory c) {
    switch (c) {
      case ShopCategory.hair:        return _hair;
      case ShopCategory.colors:      return _hairColor;
      case ShopCategory.clothes:     return _clothes;
      case ShopCategory.faces:       return _face;
      case ShopCategory.backgrounds: return _bg;
    }
  }

  void _setDraft(ShopCategory c, String id) {
    switch (c) {
      case ShopCategory.hair:        _hair = id; break;
      case ShopCategory.colors:      _hairColor = id; break;
      case ShopCategory.clothes:     _clothes = id; break;
      case ShopCategory.faces:       _face = id; break;
      case ShopCategory.backgrounds: _bg = id; break;
    }
  }

  /// `isUnlocked` for this player (see [isShopItemUnlocked]).
  bool _isOwned(ShopItem i, _ShopData s) =>
      isShopItemUnlocked(i, owned: s.owned, totalKm: s.totalKm, level: s.level) ||
      // the colour you already wear is yours
      (i.category == ShopCategory.colors &&
          i.colorHex?.toUpperCase() == s.hairColor.toUpperCase());

  /// Locked behind a kilometre milestone that is not reached yet.
  bool _isLocked(ShopItem i, _ShopData s) => !_isOwned(i, s) && (i.unlockKm > s.totalKm || i.unlockLevel > s.level);

  List<ShopItem> _draftItems() {
    final out = <ShopItem>[];
    for (final c in ShopCategory.values) {
      final id = _draftOf(c);
      if (id.isEmpty) continue;
      final item = _find(c, id);
      if (item != null) out.add(item);
    }
    return out;
  }

  int _cost(_ShopData s) => _draftItems()
      .where((i) => !_isOwned(i, s))
      .fold<int>(0, (sum, i) => sum + i.price);

  bool _changed(_ShopData s) =>
      _hair != s.hair ||
      _face != s.face ||
      _clothes != s.clothes ||
      _bg != s.bg ||
      _hairColor.toUpperCase() != s.hairColor.toUpperCase();

  /// A previewed item the player can't unlock yet (distance-gated).
  ShopItem? _lockedInDraft(_ShopData s) {
    for (final i in _draftItems()) {
      if (_isLocked(i, s)) return i;
    }
    return null;
  }

  String _kmText(double km) => km.toStringAsFixed(1); // e.g. 15.0

  Color _hex(String h) => Color(int.parse('FF${h.replaceAll('#', '')}', radix: 16));

  String _fmt(int n) => n
      .toString()
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _onItemTap(ShopItem item, _ShopData s) {
    if (!item.equippable) {
      _snack(_isLocked(item, s)
          ? '🔒 ${item.lockLabel(s.totalKm, s.level)}: ${item.name}'
          : 'Art for ${item.name} is coming soon!');
      return;
    }
    // Try-on: unowned and even distance-locked items go straight onto the
    // live mannequin. Nothing is bought until BUY EQUIPPED ITEM is tapped.
    if (_isLocked(item, s)) {
      _snack('👀 Trying on ${item.name} — ${item.lockLabel(s.totalKm, s.level)}');
    }
    setState(() {
      // tapping equipped clothes again takes them off
      if (item.category == ShopCategory.clothes && _clothes == item.id) {
        _clothes = '';
      } else {
        _setDraft(item.category,
            item.category == ShopCategory.colors ? item.colorHex! : item.id);
      }
    });
  }

  Future<void> _purchase(String uid) async {
    setState(() => _buying = true);
    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final snap = await txn.get(userRef);
        final fresh = _ShopData.from(snap.data() ?? {});

        var cost = 0;
        final newOwned = <String>[];
        for (final item in _draftItems()) {
          if (_isOwned(item, fresh)) continue;
          if (_isLocked(item, fresh)) throw 'locked';
          cost += item.price;
          newOwned.add(item.id);
        }
        if (fresh.gems < cost) throw 'gems';

        final updates = <String, dynamic>{};
        if (cost > 0) updates['gems'] = fresh.gems - cost;
        if (newOwned.isNotEmpty) updates['owned_items'] = FieldValue.arrayUnion(newOwned);
        if (_hair != fresh.hair) updates['hair_style'] = _hair;
        if (_face != fresh.face) updates['face_expression'] = _face;
        if (_hairColor.toUpperCase() != fresh.hairColor.toUpperCase()) {
          updates['hair_color'] = _hairColor;
        }
        if (_clothes != fresh.clothes) {
          updates['equipped_clothes'] = _clothes.isEmpty ? <String>[] : [_clothes];
        }
        if (_bg != fresh.bg) updates['background_id'] = _bg;
        if (updates.isNotEmpty) txn.update(userRef, updates);
      });
      _snack('✅ Look saved!');
    } catch (e) {
      _snack(e == 'gems'
          ? 'Not enough gems!'
          : e == 'locked'
              ? 'An item is still locked.'
              : 'Purchase failed. Try again.');
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  // ───────────────────────── build ─────────────────────────

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
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
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator(color: Rb.green));
            }
            final s = _ShopData.from(snap.data!.data() ?? {});

            // (Re)load the draft whenever the SAVED look changes — first load,
            // after a purchase, or after equipping in the Gear screen.
            final sig = '${s.hair}|${s.face}|${s.clothes}|${s.bg}|${s.hairColor}';
            if (sig != _sig) {
              _sig = sig;
              _hair = s.hair;
              _face = s.face;
              _clothes = s.clothes;
              _bg = s.bg;
              _hairColor = s.hairColor;
            }

            return LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 760;
              final browse = Column(
                children: [
                  _buildSearchRow(),
                  const SizedBox(height: 8),
                  _buildPills(),
                  const SizedBox(height: 10),
                  Expanded(child: _buildContent(s)),
                ],
              );

              if (wide) {
                // Roblox-style: avatar panel on the left, catalogue on the right
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 340,
                        child: SingleChildScrollView(
                          child: _buildPreviewPanel(s, uid, wide: true),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: [
                            _buildHeader(s),
                            const SizedBox(height: 8),
                            Expanded(child: browse),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Column(
                  children: [
                    _buildHeader(s),
                    const SizedBox(height: 8),
                    _buildPreviewPanel(s, uid, wide: false),
                    const SizedBox(height: 4),
                    Expanded(child: browse),
                  ],
                ),
              );
            });
          },
        ),
      ),
    );
  }

  // ───────────────────────── header ─────────────────────────

  Widget _buildHeader(_ShopData s) {
    Widget chip(String text, Color c, Color e) => Block(
          color: c,
          edge: e,
          depth: 3,
          radius: 10,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: BlockText(text, size: 11, stroke: 3),
        );

    return Block(
      color: Rb.hud,
      edge: Rb.hudEdge,
      depth: 6,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: IconLabel(
                iconPath: AppIcons.shopChest,
                iconSize: 30,
                gap: 8,
                label: BlockText('AVATAR SHOP', size: 20, stroke: 4.5),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // gamified context: your level and distance drive the unlocks
          chip('LV ${s.level}', Rb.green, Rb.greenEdge),
          const SizedBox(width: 6),
          chip('${s.totalKm.toStringAsFixed(1)} KM', Rb.orange, Rb.orangeEdge),
          const SizedBox(width: 6),
          Block(
            color: Rb.blue,
            edge: Rb.blueEdge,
            depth: 4,
            radius: 12,
            gloss: true,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: BlockText('💎 ${_fmt(s.gems)}', size: 13, stroke: 3.5),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── search + category pills ─────────────────────────

  Widget _buildSearchRow() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Rb.panel,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(0, 4), blurRadius: 0),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.white70, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtl,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
              cursorColor: Rb.neon,
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search items',
                hintStyle:
                    TextStyle(color: Colors.white38, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() {
                _query = '';
                _searchCtl.clear();
              }),
              child: const Icon(Icons.close, color: Colors.white70, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _buildPills() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 5),
        itemCount: _tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final t = _tabs[i];
          final sel = _cat == t.cat;
          return PressBlock(
            color: t.color,
            edge: t.edge,
            depth: 4,
            radius: 20,
            forcePressed: sel,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            onTap: () => setState(() => _cat = t.cat),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BlockText(t.label, size: 13, stroke: 3.5),
                const SizedBox(height: 2),
                // Roblox-style underline marks the open tab
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 3,
                  width: sel ? 28 : 0,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ───────────────────────── content: featured / grid / search ─────────────────────────

  Widget _buildContent(_ShopData s) {
    if (_query.isNotEmpty) {
      final hits = kShopCatalog
          .where((i) =>
              i.name.toLowerCase().contains(_query) &&
              (_cat == null || i.category == _cat))
          .toList();
      if (hits.isEmpty) {
        return const Center(
          child: BlockText('NO ITEMS FOUND', size: 14, stroke: 3.5),
        );
      }
      return _buildGrid(hits, s);
    }
    if (_cat == null) return _buildFeatured(s);
    return _buildGrid(kShopCatalog.where((i) => i.category == _cat).toList(), s);
  }

  Widget _buildGrid(List<ShopItem> items, _ShopData s) {
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / 150).floor().clamp(3, 6);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 10,
          mainAxisSpacing: 6,
          childAspectRatio: 0.66,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => _buildTile(items[i], s),
      );
    });
  }

  // ── Featured: next unlock, category mosaic, run-to-unlock list ──

  /// XP needed in total to REACH [level] (level n needs n*500 xp from n-1).
  int _xpForLevel(int level) => 500 * (level - 1) * level ~/ 2;

  /// 0..1 progress toward unlocking a gated item (1 = reached).
  double _progress(ShopItem i, _ShopData s) {
    var p = 1.0;
    if (i.unlockKm > 0) p = p < s.totalKm / i.unlockKm ? p : s.totalKm / i.unlockKm;
    if (i.unlockLevel > 1) {
      final need = _xpForLevel(i.unlockLevel);
      p = p < s.xp / need ? p : s.xp / need;
    }
    return p.clamp(0.0, 1.0).toDouble();
  }

  /// "3.2 km to go" / "120 XP to go"
  String _remaining(ShopItem i, _ShopData s) {
    final parts = <String>[];
    if (i.unlockKm > s.totalKm) {
      parts.add('${(i.unlockKm - s.totalKm).toStringAsFixed(1)} km to go');
    }
    if (i.unlockLevel > s.level) {
      final xp = _xpForLevel(i.unlockLevel) - s.xp;
      parts.add('${_fmt(xp < 0 ? 0 : xp)} XP to go');
    }
    return parts.join('  •  ');
  }

  Widget _buildFeatured(_ShopData s) {
    final gated = kShopCatalog
        .where((i) => (i.unlockKm > 0 || i.unlockLevel > 1) && !_isOwned(i, s))
        .toList()
      ..sort((a, b) => _progress(b, s).compareTo(_progress(a, s)));
    final next = gated.isEmpty ? null : gated.first;

    return LayoutBuilder(builder: (context, c) {
      final tileW = (c.maxWidth - 4 - 10) / 2;
      return ListView(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 16),
        children: [
          _streakCard(s),
          const SizedBox(height: 12),
          if (_weeklyPick() case final pick?) ...[
            _weeklyPickCard(pick, s),
            const SizedBox(height: 12),
          ],
          if (next != null) _nextUnlockCard(next, s),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              for (final t in _tabs.where((t) => t.cat != null))
                SizedBox(width: tileW, child: _categoryTile(t, s)),
            ],
          ),
          if (gated.length > 1) ...[
            const SizedBox(height: 10),
            const BlockText('RUN TO UNLOCK', size: 14, stroke: 3.5, color: Rb.gold),
            const SizedBox(height: 8),
            for (final i in gated.skip(1)) _unlockRow(i, s),
          ],
        ],
      );
    });
  }

  Widget _streakCard(_ShopData s) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final days = _act.streakDays;
    return Block(
      color: const Color(0xFFB5400A),
      edge: const Color(0xFF5A1F00),
      depth: 6,
      radius: 18,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BlockText('🔥 $days-DAY STREAK', size: 15, stroke: 4),
              const Spacer(),
              const BlockText('run daily for gems', size: 9, stroke: 2.5),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final r in _streakRewards) ...[
                Expanded(child: _streakChip(uid, s, r.$1, r.$2, days)),
                if (r != _streakRewards.last) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _streakChip(String? uid, _ShopData s, int need, int gems, int days) {
    final key = _streakKey(need);
    final claimed = key.isNotEmpty && s.streakClaims.contains(key);
    final ready = days >= need && !claimed && uid != null;
    final Color c = claimed ? Rb.panel : (ready ? Rb.green : Rb.slate);
    final Color e = claimed ? Rb.panelEdge : (ready ? Rb.greenEdge : Rb.slateEdge);
    return PressBlock(
      color: c,
      edge: e,
      depth: 4,
      radius: 12,
      forcePressed: claimed,
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
      onTap: ready && !_claiming ? () => _claimStreak(uid!, need, gems) : null,
      child: Column(
        children: [
          BlockText('${need}D', size: 12, stroke: 3.5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: BlockText(
              claimed ? '✔' : '💎$gems',
              size: 11,
              stroke: 3,
              color: claimed ? Rb.neon : (ready ? Colors.white : Rb.gold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weeklyPickCard(ShopItem i, _ShopData s) {
    final owned = _isOwned(i, s);
    return PressBlock(
      color: const Color(0xFF5B3A9E),
      edge: const Color(0xFF2A1A52),
      depth: 6,
      radius: 18,
      padding: const EdgeInsets.all(12),
      onTap: () => _onItemTap(i, s),
      child: Row(
        children: [
          SizedBox(width: 84, height: 84, child: _artBox(i, s)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BlockText('⭐ WEEKLY PICK', size: 11, stroke: 3, color: Rb.gold),
                    const Spacer(),
                    BlockText(Weekly.countdown(DateTime.now()), size: 9, stroke: 2.5),
                  ],
                ),
                const SizedBox(height: 2),
                BlockText(i.name, size: 17, stroke: 4, maxLines: 1),
                const SizedBox(height: 6),
                BlockText(
                  owned ? '✔ OWNED' : '💎 ${i.price}  •  tap to try it on',
                  size: 11,
                  stroke: 3,
                  color: owned ? Rb.neon : Colors.white,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nextUnlockCard(ShopItem i, _ShopData s) {
    return Block(
      color: const Color(0xFFB8860B),
      edge: const Color(0xFF5A4305),
      depth: 6,
      radius: 18,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(width: 84, height: 84, child: _artBox(i, s)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BlockText('NEXT UNLOCK', size: 11, stroke: 3),
                const SizedBox(height: 2),
                BlockText(i.name, size: 18, stroke: 4, maxLines: 1),
                const SizedBox(height: 8),
                BlockBar(value: _progress(i, s), height: 14, color: Rb.neon),
                const SizedBox(height: 4),
                BlockText(_remaining(i, s), size: 10, stroke: 2.5),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _unlockRow(ShopItem i, _ShopData s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Block(
        color: Rb.slate,
        edge: Rb.slateEdge,
        depth: 4,
        radius: 14,
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            SizedBox(width: 52, height: 52, child: _artBox(i, s)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BlockText(i.name, size: 13, stroke: 3, maxLines: 1),
                  const SizedBox(height: 5),
                  BlockBar(value: _progress(i, s), height: 9, color: Rb.green),
                  const SizedBox(height: 3),
                  BlockText(_remaining(i, s),
                      size: 9, stroke: 2.5, color: const Color(0xFFB8BDC4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Colourful category card (like Roblox's collection tiles).
  Widget _categoryTile(_TabDef t, _ShopData s) {
    final items = kShopCatalog.where((i) => i.category == t.cat).toList();
    final owned = items.where((i) => _isOwned(i, s)).length;
    final shown = items.where((i) => i.equippable).take(2).toList();
    return PressBlock(
      color: t.color,
      edge: t.edge,
      depth: 6,
      radius: 16,
      padding: const EdgeInsets.all(10),
      onTap: () => setState(() => _cat = t.cat),
      child: SizedBox(
        height: 112,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BlockText(t.label, size: 14, stroke: 3.5),
            const SizedBox(height: 6),
            Expanded(
              child: Row(
                children: [
                  for (final i in shown)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _artBox(i, s),
                      ),
                    ),
                  if (shown.isEmpty) const Spacer(),
                ],
              ),
            ),
            const SizedBox(height: 6),
            BlockText('$owned / ${items.length} OWNED', size: 9, stroke: 2.5),
          ],
        ),
      ),
    );
  }

  /// Rounded grey display box with the item's art (no overlays).
  Widget _artBox(ShopItem item, _ShopData s) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFCBD5E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black, width: 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: _preview(item, s),
      ),
    );
  }

  // ───────────────────────── item tiles ─────────────────────────

  /// Frame colour by rarity: common / rare / epic / milestone.
  ({Color c, Color e, String label}) _rarity(ShopItem i) {
    if (i.unlockKm > 0 || i.unlockLevel > 1) {
      return (c: const Color(0xFF9A6B00), e: const Color(0xFF4A3300), label: 'MILESTONE');
    }
    if (i.price >= 150) {
      return (c: const Color(0xFF5B3A9E), e: const Color(0xFF2A1A52), label: 'EPIC');
    }
    if (i.price > 0) {
      return (c: const Color(0xFF1E5F8F), e: const Color(0xFF0A2B45), label: 'RARE');
    }
    return (c: Rb.slate, e: Colors.black, label: 'COMMON');
  }

  Widget _buildTile(ShopItem item, _ShopData s) {
    final isUnlocked = _isOwned(item, s); // false = lock overlay
    final owned = isUnlocked;
    final locked = _isLocked(item, s);
    final equipped = item.category == ShopCategory.colors
        ? _hairColor.toUpperCase() == item.colorHex?.toUpperCase()
        : _draftOf(item.category) == item.id;
    final r = _rarity(item);

    return PressBlock(
      color: equipped ? const Color(0xFF1E4A66) : r.c,
      edge: equipped ? Rb.neon : r.e,
      depth: 6,
      radius: 14,
      forcePressed: equipped,
      padding: const EdgeInsets.all(6),
      onTap: () => _onItemTap(item, s),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: item.category == ShopCategory.faces
                    ? const Color(0xFFE6E9ED)
                    : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black, width: 3),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _preview(item, s),
                    if (locked)
                      _lockMask(item, s)
                    else if (!isUnlocked)
                      _premiumLock(), // priced item, not bought yet
                    if (!locked && r.label != 'COMMON')
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Container(
                          margin: const EdgeInsets.all(3),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: r.c,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: Colors.black, width: 1.5),
                          ),
                          child: BlockText(r.label, size: 7, stroke: 2),
                        ),
                      ),
                    if (equipped && owned)
                      Align(
                        alignment: Alignment.topLeft,
                        child: Container(
                          margin: const EdgeInsets.all(3),
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Rb.green,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.black, width: 2),
                          ),
                          child: const Icon(Icons.check, color: Colors.white, size: 13),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: BlockText(item.name, size: 11, stroke: 3, maxLines: 1),
          ),
          const SizedBox(height: 6),
          _tag(item, owned: owned, locked: locked, equipped: equipped),
        ],
      ),
    );
  }

  Widget _tag(ShopItem item,
      {required bool owned, required bool locked, required bool equipped}) {
    Color fill, edge;
    String text;
    if (locked) {
      fill = Rb.panel; edge = Rb.panelEdge; text = '🔒 LOCKED';
    } else if (equipped && owned) {
      fill = Rb.green; edge = Rb.greenEdge; text = '✔ EQUIPPED';
    } else if (owned) {
      fill = Rb.slot; edge = Rb.slateEdge; text = 'OWNED';
    } else if (item.price == 0) {
      fill = Rb.neon; edge = Rb.greenEdge; text = 'FREE';
    } else {
      fill = Rb.green; edge = Rb.greenEdge; text = '💎 ${item.price}';
    }
    return Block(
      color: fill,
      edge: edge,
      depth: 3,
      radius: 8,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        width: double.infinity,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: BlockText(text, size: 12, stroke: 3.5),
          ),
        ),
      ),
    );
  }

  Widget _lockMask(ShopItem item, _ShopData s) {
    return Container(
      color: const Color(0xEE3A3D40),
      padding: const EdgeInsets.all(5),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, color: Colors.white, size: 22),
            const SizedBox(height: 3),
            BlockText(
              item.lockLabel(s.totalKm, s.level),
              size: 8.5,
              stroke: 3,
              align: TextAlign.center,
            ),
            const SizedBox(height: 5),
            BlockBar(value: _progress(item, s), height: 7, color: Rb.neon),
          ],
        ),
      ),
    );
  }

  /// Dim scrim + padlock on a premium item the player has not bought yet
  /// (the art stays visible so it can still be tried on).
  Widget _premiumLock() {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0x553A3D40)),
        Align(
          alignment: Alignment.topRight,
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.lock, color: Rb.gold, size: 15),
          ),
        ),
      ],
    );
  }

  /// Standalone preview of just the item's asset.
  Widget _preview(ShopItem item, _ShopData s) {
    if (item.category == ShopCategory.backgrounds) {
      return BlockBackground(id: item.id);
    }
    if (item.asset == null && item.category != ShopCategory.colors) {
      return Center(child: Text(item.emoji, style: const TextStyle(fontSize: 44)));
    }
    switch (item.category) {
      case ShopCategory.colors:
        return Center(
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _hex(item.colorHex!),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black, width: 3),
              boxShadow: const [BoxShadow(color: Colors.black54, offset: Offset(0, 4))],
            ),
            child: const Center(child: Text('💇', style: TextStyle(fontSize: 24))),
          ),
        );
      case ShopCategory.hair:
        return ShopCropImage(path: item.asset!, focusX: 141, focusY: 112, zoom: 1.0);
      case ShopCategory.faces:
        return ShopCropImage(path: item.asset!, focusX: 142.5, focusY: 178, zoom: 1.9);
      default: // clothes: show the version made for the hero's body
        final mine = clothesAssetFor(s.bodyId, item.id, gender: s.gender);
        return ShopCropImage(
          path: mine.isEmpty ? item.asset! : mine,
          fallbackPath: item.asset,
          focusX: 142.5,
          focusY: 252,
          zoom: 0.55,
        );
    }
  }

  // ───────────────────────── avatar preview panel ─────────────────────────

  Widget _buildPreviewPanel(_ShopData s, String uid, {required bool wide}) {
    final items = _draftItems();
    final cost = _cost(s);

    if (wide) {
      return Block(
        color: Rb.slate,
        edge: Rb.slateEdge,
        depth: 6,
        radius: 18,
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _buildLiveAvatar(s, width: double.infinity, height: 380),
            const SizedBox(height: 10),
            _buildSummary(items, cost, s, height: 120),
            const SizedBox(height: 10),
            _buildActionRow(s, uid),
          ],
        ),
      );
    }

    return Block(
      color: Rb.slate,
      edge: Rb.slateEdge,
      depth: 6,
      radius: 18,
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLiveAvatar(s, width: 112, height: 176),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: [
                _buildSummary(items, cost, s, height: 92),
                const SizedBox(height: 8),
                _buildActionRow(s, uid),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Cancel (red) + Save/Buy (state-aware), like the Roblox editor.
  Widget _buildActionRow(_ShopData s, String uid) {
    final cost = _cost(s);
    final changed = _changed(s);
    final broke = cost > s.gems;

    String label;
    String? sub;
    Color fill = Rb.green, edge = Rb.greenEdge;
    VoidCallback? onTap;
    if (_buying) {
      label = 'SAVING…';
      fill = Rb.panel; edge = Rb.panelEdge;
    } else if (_lockedInDraft(s) != null) {
      final l = _lockedInDraft(s)!;
      label = l.unlockLevel > s.level
          ? '🔒 LV ${l.unlockLevel}'
          : '🔒 ${_kmText(l.unlockKm)} KM';
      sub = 'Remove ${l.name}';
      fill = const Color(0xFF4A4F55); edge = Rb.panelEdge;
    } else if (!changed) {
      label = 'SAVE';
      sub = 'Tap items to try on';
      fill = Rb.panel; edge = Rb.panelEdge;
    } else if (cost == 0) {
      label = 'OWNED';
      sub = 'Equip in GEAR';
      fill = Rb.panel; edge = Rb.panelEdge;
    } else if (broke) {
      label = 'NEED ${_fmt(cost - s.gems)} 💎';
      fill = Rb.red; edge = Rb.redEdge;
    } else {
      label = 'BUY';
      sub = '💎 ${_fmt(cost)}';
      onTap = () => _purchase(uid);
    }

    return Row(
      children: [
        Expanded(
          flex: 4,
          child: PressBlock(
            color: changed && !_buying ? Rb.red : Rb.panel,
            edge: changed && !_buying ? Rb.redEdge : Rb.panelEdge,
            depth: 6,
            radius: 20,
            padding: const EdgeInsets.symmetric(vertical: 12),
            onTap: changed && !_buying
                ? () => setState(() {
                      _hair = s.hair;
                      _face = s.face;
                      _clothes = s.clothes;
                      _bg = s.bg;
                      _hairColor = s.hairColor;
                    })
                : null,
            child: const Center(child: BlockText('CANCEL', size: 14, stroke: 3.5)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 5,
          child: PressBlock(
            color: fill,
            edge: edge,
            depth: 6,
            radius: 20,
            padding: const EdgeInsets.symmetric(vertical: 8),
            onTap: onTap,
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: BlockText(label, size: 15, stroke: 4),
                  ),
                  if (sub != null)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: BlockText(sub, size: 9.5, stroke: 2.5),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Live 286x512 AvatarPreview with the draft look + chosen background.
  Widget _buildLiveAvatar(_ShopData s,
      {required double width, required double height}) {
    return Block(
      color: const Color(0xFF8FD0FF),
      edge: Colors.black,
      depth: 4,
      radius: 14,
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            fit: StackFit.expand,
            children: [
              BlockBackground(id: _bg),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 2),
                child: FittedBox(
                  fit: BoxFit.contain,
                  clipBehavior: Clip.none,
                  child: SizedBox(
                    width: kSpriteWidth,
                    height: kSpriteHeight + 48,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          top: 44,
                          width: kSpriteWidth,
                          height: kSpriteHeight,
                          child: AvatarPreview(
                            bodySize: s.bodyId,
                            expression: _face,
                            hairStyle: _hair,
                            activeGear: _clothes,
                            skinTone: s.skinTone,
                            hairColor: _hairColor,
                            gender: s.gender,
                            // drawn small, so filter instead of dropping pixels
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummary(List<ShopItem> items, int cost, _ShopData s,
      {required double height}) {
    return Block(
      color: Rb.panel,
      edge: Rb.panelEdge,
      depth: 4,
      radius: 14,
      padding: const EdgeInsets.all(10),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final i in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Text(_catIcon(i.category), style: const TextStyle(fontSize: 13)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              i.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            _isOwned(i, s) ? 'OWNED' : '💎 ${i.price}',
                            style: TextStyle(
                              color: _isOwned(i, s) ? Rb.neon : Rb.gold,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(color: Colors.black54, thickness: 2, height: 8),
            Row(
              children: [
                const BlockText('TOTAL', size: 11, stroke: 3),
                const Spacer(),
                BlockText('💎 ${_fmt(cost)}', size: 13, stroke: 3.5, color: Rb.gold),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _catIcon(ShopCategory c) => _cats.firstWhere((e) => e.$1 == c).$2;
}

class _TabDef {
  final ShopCategory? cat; // null = FEATURED
  final String label;
  final Color color, edge;
  const _TabDef(this.cat, this.label, this.color, this.edge);
}

const List<_TabDef> _tabs = [
  _TabDef(null, 'FEATURED', Color(0xFF7B4DFF), Color(0xFF3A1F8F)),
  _TabDef(ShopCategory.hair, 'HAIR', Color(0xFFE5484D), Color(0xFF7A1C20)),
  _TabDef(ShopCategory.colors, 'COLORS', Color(0xFFFF7A00), Color(0xFF8F3F00)),
  _TabDef(ShopCategory.clothes, 'CLOTHING', Color(0xFF00B06F), Color(0xFF006B44)),
  _TabDef(ShopCategory.faces, 'FACES', Color(0xFF9B59FF), Color(0xFF4B2A8A)),
  _TabDef(ShopCategory.backgrounds, 'SCENES', Color(0xFF00A2FF), Color(0xFF004F7A)),
];

// ───────────────────────── Cropped asset preview ─────────────────────────

/// Shows part of a 286x512 layer PNG: centres on (focusX, focusY) in canvas
/// pixels, scaled by `zoom` relative to the box width. Used so a hair/face/
/// outfit PNG (mostly transparent canvas) fills its item box nicely.
class ShopCropImage extends StatelessWidget {
  final String path;

  /// Drawn instead when [path] is missing from the project.
  final String? fallbackPath;
  final double focusX, focusY, zoom;

  const ShopCropImage({
    required this.path,
    this.fallbackPath,
    required this.focusX,
    required this.focusY,
    required this.zoom,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final z = zoom * c.maxWidth / kSpriteWidth;
      return Stack(
        children: [
          Positioned(
            left: c.maxWidth / 2 - focusX * z,
            top: c.maxHeight / 2 - focusY * z,
            width: kSpriteWidth * z,
            height: kSpriteHeight * z,
            child: Image.asset(
              path,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.none,
              errorBuilder: (_, __, ___) => fallbackPath == null
                  ? const SizedBox.shrink()
                  : Image.asset(
                      fallbackPath!,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.none,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
            ),
          ),
        ],
      );
    });
  }
}
