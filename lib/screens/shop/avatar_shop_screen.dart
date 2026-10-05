import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/asset_paths.dart';
import '../../models/character_profile.dart';
import '../../widgets/avatar_layer_stack.dart' show kSpriteWidth, kSpriteHeight;
import '../../widgets/avatar_preview.dart';
import '../../widgets/block_ui.dart';

// ═════════════════════════════════════════════════════════════════
//  Avatar Item Shop — direct purchase (replaces the gacha screen)
//
//  Firestore (users/{uid}) fields used:
//    gems            int      currency
//    total_km        double   milestone unlocks
//    owned_items     [String] bought item ids
//    hair_style / face_expression / equipped_clothes / background_id
//                             saved look
// ═════════════════════════════════════════════════════════════════

// ───────────────────────── Catalog ─────────────────────────

enum ShopCategory { hair, clothes, faces, backgrounds }

class ShopItem {
  final String id;          // must match HairStyle / FaceExpression / clothes / background ids
  final ShopCategory category;
  final String name;
  final int price;          // gems; 0 = free
  final double unlockKm;    // > 0 = locked until this many total km
  final String? asset;      // PNG key (hair / clothes / faces)
  final String emoji;       // fallback icon when there's no art yet

  const ShopItem({
    required this.id,
    required this.category,
    required this.name,
    this.price = 0,
    this.unlockKm = 0,
    this.asset,
    this.emoji = '📦',
  });

  /// Free and not milestone-gated = everyone owns it from the start.
  bool get isFree => price == 0 && unlockKm == 0;

  /// Can be shown on the avatar (has art, or is a background).
  bool get equippable => category == ShopCategory.backgrounds || asset != null;
}

/// Only items whose art really exists in assets/. Add a line to add an item.
const List<ShopItem> kShopCatalog = [
  // 💇 HAIR (ids = HairStyle ids)
  ShopItem(id: 'short_crop', category: ShopCategory.hair, name: 'Short Crop',
      asset: '$kHairDir/hair_14_short_crop.png', emoji: '💇'),
  ShopItem(id: 'warrior_spiky', category: ShopCategory.hair, name: 'Warrior Spiky',
      price: 120, asset: '$kHairDir/hair_01_warrior_spiky.png', emoji: '💇'),
  ShopItem(id: 'classic_pompadour', category: ShopCategory.hair, name: 'Pompadour',
      price: 150, asset: '$kHairDir/hair_03_classic_pompadour.png', emoji: '💇'),
  ShopItem(id: 'wavy_mane', category: ShopCategory.hair, name: 'Wavy Mane',
      price: 200, asset: '$kHairDir/hair_05_wavy_mane.png', emoji: '💇'),
  ShopItem(id: 'long_flowing', category: ShopCategory.hair, name: 'Long & Flowing',
      price: 250, unlockKm: 25, asset: '$kHairDir/hair_07_long_flowing.png', emoji: '💇'),

  // 🎽 CLOTHES
  ShopItem(id: 'outfit_01', category: ShopCategory.clothes, name: 'Training Set',
      asset: '$kClothesDir/outfit_01.png', emoji: '🎽'),
  // Milestone reward with no art yet (shows as locked / "art coming soon")
  ShopItem(id: 'slayer_boots', category: ShopCategory.clothes, name: 'Slayer Iron Boots',
      unlockKm: 15, emoji: '🥾'),

  // 🎭 FACES
  ShopItem(id: 'neutral', category: ShopCategory.faces, name: 'Neutral',
      asset: '$kFaceDir/expression_01.png', emoji: '🎭'),

  // 🌌 BACKGROUNDS (ids = BlockBackground ids)
  ShopItem(id: 'valley', category: ShopCategory.backgrounds, name: 'Verdant Vale', emoji: '🌳'),
  ShopItem(id: 'boss_map', category: ShopCategory.backgrounds, name: 'Boss Map',
      price: 100, emoji: '🗺️'),
  ShopItem(id: 'ashen', category: ShopCategory.backgrounds, name: 'Ashen Peaks',
      price: 150, emoji: '🌋'),
  ShopItem(id: 'frozen', category: ShopCategory.backgrounds, name: 'Frozen Tundra',
      price: 200, unlockKm: 35, emoji: '❄️'),
];

const List<(ShopCategory, String, String)> _cats = [
  (ShopCategory.hair, '💇', 'HAIR'),
  (ShopCategory.clothes, '🎽', 'CLOTHES'),
  (ShopCategory.faces, '🎭', 'FACES'),
  (ShopCategory.backgrounds, '🌌', 'BACKGROUNDS'),
];

// ───────────────────────── Saved data ─────────────────────────

class _ShopData {
  final int gems;
  final double totalKm;
  final Set<String> owned;
  final String hair, face, clothes, bg;
  final String bodyId, skinTone, hairColor;

  const _ShopData({
    required this.gems,
    required this.totalKm,
    required this.owned,
    required this.hair,
    required this.face,
    required this.clothes,
    required this.bg,
    required this.bodyId,
    required this.skinTone,
    required this.hairColor,
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
        ? 'outfit_01'
        : (clothesList.isEmpty ? '' : clothesList.first);

    final ownedRaw = d['owned_items'];

    return _ShopData(
      gems: (d['gems'] as num?)?.toInt() ?? 0,
      totalKm: (d['total_km'] as num?)?.toDouble() ?? 0.0,
      owned: ownedRaw is List ? ownedRaw.whereType<String>().toSet() : <String>{},
      hair: p.hairStyle.id,
      face: p.faceExpression.id,
      clothes: clothes,
      bg: (d['background_id'] as String?) ?? 'valley',
      bodyId: tier.id,
      skinTone: p.skinTone,
      hairColor: p.hairColor,
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
  ShopCategory _cat = ShopCategory.hair;

  // Draft look = what the live preview shows (not saved until purchase).
  bool _init = false;
  String _hair = '', _face = '', _clothes = '', _bg = '';

  bool _drawerOpen = true;
  bool _buying = false;

  // ── helpers ──

  ShopItem? _find(ShopCategory c, String id) {
    for (final i in kShopCatalog) {
      if (i.category == c && i.id == id) return i;
    }
    return null;
  }

  String _draftOf(ShopCategory c) {
    switch (c) {
      case ShopCategory.hair:        return _hair;
      case ShopCategory.clothes:     return _clothes;
      case ShopCategory.faces:       return _face;
      case ShopCategory.backgrounds: return _bg;
    }
  }

  void _setDraft(ShopCategory c, String id) {
    switch (c) {
      case ShopCategory.hair:        _hair = id; break;
      case ShopCategory.clothes:     _clothes = id; break;
      case ShopCategory.faces:       _face = id; break;
      case ShopCategory.backgrounds: _bg = id; break;
    }
  }

  bool _isOwned(ShopItem i, _ShopData s) => i.isFree || s.owned.contains(i.id);
  bool _isLocked(ShopItem i, _ShopData s) => !_isOwned(i, s) && i.unlockKm > s.totalKm;

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
      _hair != s.hair || _face != s.face || _clothes != s.clothes || _bg != s.bg;

  String _kmText(double km) =>
      km == km.roundToDouble() ? km.toInt().toString() : km.toStringAsFixed(1);

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
    if (_isLocked(item, s)) {
      _snack('🔒 Run ${_kmText(item.unlockKm)} Total KM to unlock ${item.name}');
      return;
    }
    if (!item.equippable) {
      _snack('Art for ${item.name} is coming soon!');
      return;
    }
    setState(() {
      // tapping equipped clothes again takes them off
      if (item.category == ShopCategory.clothes && _clothes == item.id) {
        _clothes = '';
      } else {
        _setDraft(item.category, item.id);
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

            if (!_init) {
              _hair = s.hair;
              _face = s.face;
              _clothes = s.clothes;
              _bg = s.bg;
              _init = true;
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    children: [
                      _buildHeader(s),
                      const SizedBox(height: 4),
                      _buildTabs(),
                    ],
                  ),
                ),
                Expanded(child: _buildGrid(s)),
                _buildDrawer(s, uid),
              ],
            );
          },
        ),
      ),
    );
  }

  // ───────────────────────── header + tabs ─────────────────────────

  Widget _buildHeader(_ShopData s) {
    return Block(
      color: Rb.panel,
      edge: Rb.panelEdge,
      depth: 6,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: BlockText('🛒 AVATAR SHOP', size: 20, stroke: 4.5),
            ),
          ),
          const SizedBox(width: 8),
          Block(
            color: Rb.blue,
            edge: Rb.blueEdge,
            depth: 4,
            radius: 12,
            gloss: true,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: BlockText('💎 ${_fmt(s.gems)} GEMS', size: 13, stroke: 3.5),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Row(
      children: [
        for (var i = 0; i < _cats.length; i++) ...[
          Expanded(child: _buildTab(_cats[i])),
          if (i != _cats.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _buildTab((ShopCategory, String, String) c) {
    final sel = _cat == c.$1;
    return PressBlock(
      color: sel ? Rb.blue : Rb.panel,
      edge: sel ? Rb.blueEdge : Rb.panelEdge,
      depth: 5,
      radius: 12,
      forcePressed: sel,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      onTap: () => setState(() => _cat = c.$1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(c.$2, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: BlockText(c.$3, size: 9, stroke: 2.5),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── item grid ─────────────────────────

  Widget _buildGrid(_ShopData s) {
    final items = kShopCatalog.where((i) => i.category == _cat).toList();

    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 600 ? 3 : 2;
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 12,
          mainAxisSpacing: 4,
          childAspectRatio: 0.82,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => _buildTile(items[i], s),
      );
    });
  }

  Widget _buildTile(ShopItem item, _ShopData s) {
    final owned = _isOwned(item, s);
    final locked = _isLocked(item, s);
    final equipped = _draftOf(item.category) == item.id;

    return PressBlock(
      color: equipped ? const Color(0xFF1E4A66) : Rb.slate,
      edge: equipped ? Rb.blueEdge : Rb.slateEdge,
      depth: 6,
      radius: 14,
      forcePressed: equipped,
      padding: const EdgeInsets.all(8),
      onTap: () => _onItemTap(item, s),
      child: Column(
        children: [
          // inner display box
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
                    _preview(item),
                    if (locked) _lockMask(item),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: BlockText(item.name, size: 12, stroke: 3, maxLines: 1),
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
      fill = Rb.green; edge = Rb.greenEdge; text = 'BUY 💎 ${item.price}';
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
            child: BlockText(text, size: 12, stroke: 3),
          ),
        ),
      ),
    );
  }

  Widget _lockMask(ShopItem item) {
    return Container(
      color: Colors.black.withValues(alpha: 0.68),
      padding: const EdgeInsets.all(6),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, color: Colors.white, size: 26),
            const SizedBox(height: 4),
            BlockText(
              'Lock: Run ${_kmText(item.unlockKm)} Total KM to Unlock',
              size: 10,
              stroke: 3,
              align: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Standalone preview of just the item's asset.
  Widget _preview(ShopItem item) {
    if (item.category == ShopCategory.backgrounds) {
      return BlockBackground(id: item.id);
    }
    if (item.asset == null) {
      return Center(child: Text(item.emoji, style: const TextStyle(fontSize: 44)));
    }
    switch (item.category) {
      case ShopCategory.hair:
        return _CropImage(path: item.asset!, focusX: 141, focusY: 112, zoom: 1.0);
      case ShopCategory.faces:
        return _CropImage(path: item.asset!, focusX: 142.5, focusY: 178, zoom: 1.9);
      default: // clothes
        return _CropImage(path: item.asset!, focusX: 142.5, focusY: 252, zoom: 0.55);
    }
  }

  // ───────────────────────── live preview drawer ─────────────────────────

  Widget _buildDrawer(_ShopData s, String uid) {
    final items = _draftItems();
    final cost = _cost(s);
    final changed = _changed(s);
    final broke = cost > s.gems;

    // ── purchase button state ──
    String label;
    String? sub;
    Color fill = Rb.neon, edge = Rb.greenEdge;
    VoidCallback? onTap;
    if (_buying) {
      label = 'PROCESSING…';
      fill = Rb.panel; edge = Rb.panelEdge;
    } else if (!changed) {
      label = '✔ ALREADY EQUIPPED';
      fill = Rb.panel; edge = Rb.panelEdge;
    } else if (cost == 0) {
      label = '✅ SAVE LOOK';
      onTap = () => _purchase(uid);
    } else if (broke) {
      label = 'NEED ${_fmt(cost - s.gems)} MORE 💎';
      fill = Rb.red; edge = Rb.redEdge;
    } else {
      label = '🛒 PURCHASE EQUIPPED';
      sub = '💎 ${_fmt(cost)}';
      onTap = () => _purchase(uid);
    }

    return Container(
      decoration: const BoxDecoration(
        color: Rb.panel,
        border: Border(top: BorderSide(color: Colors.black, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drawer handle
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _drawerOpen = !_drawerOpen),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    BlockText(_drawerOpen ? 'YOUR LOOK ▼' : 'YOUR LOOK ▲',
                        size: 11, stroke: 3),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: _drawerOpen
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLiveAvatar(s),
                          const SizedBox(width: 12),
                          Expanded(child: _buildSummary(items, cost, s)),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            SizedBox(
              width: double.infinity,
              child: PressBlock(
                color: fill,
                edge: edge,
                depth: 8,
                radius: 16,
                padding: const EdgeInsets.symmetric(vertical: 14),
                onTap: onTap,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(child: BlockText(label, size: 20, stroke: 4.5)),
                    if (sub != null) ...[
                      const SizedBox(height: 2),
                      Center(child: BlockText(sub, size: 13, stroke: 3, color: Rb.gold)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Live 286x512 AvatarPreview with the draft look + chosen background.
  Widget _buildLiveAvatar(_ShopData s) {
    return Block(
      color: const Color(0xFF8FD0FF),
      edge: Colors.black,
      depth: 4,
      radius: 14,
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: 120,
        height: 190,
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
                            hairColor: s.hairColor,
                            // drawn at ~1/3 scale, so filter instead of dropping pixels
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

  Widget _buildSummary(List<ShopItem> items, int cost, _ShopData s) {
    return Block(
      color: Rb.slate,
      edge: Rb.slateEdge,
      depth: 4,
      radius: 14,
      padding: const EdgeInsets.all(10),
      child: SizedBox(
        height: 170,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final i in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        children: [
                          Text(_catIcon(i.category), style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              i.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            _isOwned(i, s) ? 'OWNED' : '💎 ${i.price}',
                            style: TextStyle(
                              color: _isOwned(i, s) ? Rb.neon : Rb.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(color: Colors.black54, thickness: 2, height: 10),
            Row(
              children: [
                const BlockText('TOTAL', size: 12, stroke: 3),
                const Spacer(),
                BlockText('💎 ${_fmt(cost)}', size: 14, stroke: 3.5, color: Rb.gold),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'You have 💎 ${_fmt(s.gems)}',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _catIcon(ShopCategory c) => _cats.firstWhere((e) => e.$1 == c).$2;
}

// ───────────────────────── Cropped asset preview ─────────────────────────

/// Shows part of a 286x512 layer PNG: centres on (focusX, focusY) in canvas
/// pixels, scaled by `zoom` relative to the box width. Used so a hair/face/
/// outfit PNG (mostly transparent canvas) fills its item box nicely.
class _CropImage extends StatelessWidget {
  final String path;
  final double focusX, focusY, zoom;

  const _CropImage({
    required this.path,
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
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ],
      );
    });
  }
}