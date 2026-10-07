import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/character_profile.dart';
import '../../models/outfit_catalog.dart';
import '../../utils/player_stats.dart' show LevelProgress;
import '../../widgets/avatar_layer_stack.dart' show kSpriteWidth, kSpriteHeight;
import '../../widgets/avatar_preview.dart';
import '../../widgets/block_ui.dart';
import '../shop/avatar_shop_screen.dart'
    show ShopItem, ShopCategory, ShopCropImage, kShopCatalog, isShopItemUnlocked;

// ═════════════════════════════════════════════════════════════════
//  GEAR — inventory chest. Only items the player ALREADY OWNS.
//  (Buying and try-on of unowned items lives in the Shop.)
//
//  Reads  users/{uid}: owned_items, equipped_clothes + the saved look
//  Writes users/{uid}: equipped_clothes
// ═════════════════════════════════════════════════════════════════

class _SlotDef {
  final String id, label, emoji;
  const _SlotDef(this.id, this.label, this.emoji);
}

const _slots = [
  _SlotDef('weapon', 'WEAPON', '⚔️'),
  _SlotDef('armor', 'ARMOR', '🛡️'),
  _SlotDef('boots', 'BOOTS', '🥾'),
  _SlotDef('ring', 'RING', '💍'),
];

class EquipmentScreen extends StatefulWidget {
  const EquipmentScreen({super.key});

  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen> {
  String? _slotFilter; // tapped slot -> filters INVENTORY
  String _savedSig = '';
  String _draft = ''; // clothes id shown on the preview ('' = none)
  bool _saving = false;

  // refreshed from the user doc on every snapshot
  Set<String> _unlocked = <String>{}; // ids the hero may wear (isUnlocked)
  double _totalKm = 0;
  int _level = 1;
  String _bodyId = 'normal';
  String? _gender;

  List<ShopItem> get _clothes =>
      kShopCatalog.where((i) => i.category == ShopCategory.clothes).toList();

  ShopItem? _byId(String id) {
    for (final i in _clothes) {
      if (i.id == id) return i;
    }
    return null;
  }

  static String _savedClothes(Map<String, dynamic> d) {
    final raw = d['equipped_clothes'];
    if (raw is! List) return StarterPack.activeOutfit; // same default as the avatar
    final l = raw.whereType<String>().toList();
    return l.isEmpty ? '' : normalizeOutfitId(l.first);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _equip(String uid) async {
    // never save gear the hero has not unlocked
    if (_draft.isNotEmpty && !_unlocked.contains(_draft)) {
      _snack('🔒 That item is still locked.');
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'equipped_clothes': _draft.isEmpty ? <String>[] : [_draft],
      });
      _snack('⚔️ Gear equipped!');
    } catch (_) {
      _snack('Could not save. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
          stream:
              FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator(color: Rb.green));
            }
            final data = snap.data!.data() ?? <String, dynamic>{};
            final saved = _savedClothes(data);

            // reload the draft whenever the saved gear changes
            if (saved != _savedSig) {
              _savedSig = saved;
              _draft = saved;
            }

            final ownedRaw = data['owned_items'];
            final owned = ownedRaw is List
                ? ownedRaw.whereType<String>().toSet()
                : <String>{};
            _totalKm = (data['total_km'] as num?)?.toDouble() ?? 0.0;
            _level = LevelProgress.fromXp((data['xp'] as num?)?.toInt() ?? 0).level;
            _unlocked = {
              for (final i in _clothes)
                if (isShopItemUnlocked(i, owned: owned, totalKm: _totalKm, level: _level)) i.id,
            };
            final p = CharacterProfile.fromFirestore(data);
            final storedTier = data['body_tier'] as String?;
            _bodyId = ((p.heightCm == null || p.weightKg == null) && storedTier != null
                    ? BodyTierExt.fromId(storedTier)
                    : p.bodyTier)
                .id;
            _gender = p.gender;

            // every clothing item is listed; locked ones carry a lock overlay
            final inventory = _clothes;

            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                children: [
                  _header(_unlocked.length),
                  const SizedBox(height: 12),
                  Expanded(flex: 11, child: _stage(data)),
                  const SizedBox(height: 10),
                  _equipButton(uid, saved),
                  const SizedBox(height: 12),
                  Expanded(flex: 9, child: _inventory(inventory)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── header ───────────────────────────────────────────────────────────
  Widget _header(int count) => Block(
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
                child: BlockText('🎒 GEAR CHEST', size: 20, stroke: 4.5),
              ),
            ),
            Block(
              color: Rb.blue,
              edge: Rb.blueEdge,
              depth: 4,
              radius: 10,
              gloss: true,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: BlockText('$count OWNED', size: 11, stroke: 3),
            ),
          ],
        ),
      );

  // ── slots + live character ───────────────────────────────────────────
  Widget _stage(Map<String, dynamic> data) {
    final equippedItem = _byId(_draft);

    Widget slot(_SlotDef d) {
      final isSel = _slotFilter == d.id;
      final here = equippedItem?.slot == d.id ? equippedItem : null;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: PressBlock(
            color: isSel ? Rb.gold : Rb.slate,
            edge: isSel ? Rb.goldEdge : Colors.black,
            depth: 6,
            radius: 14,
            forcePressed: isSel,
            padding: const EdgeInsets.all(4),
            onTap: () => setState(() => _slotFilter = isSel ? null : d.id),
            child: SizedBox.expand(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(here?.emoji ?? d.emoji,
                      style: TextStyle(
                          fontSize: 26,
                          color: Colors.white.withValues(alpha: here == null ? 0.45 : 1))),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: BlockText(d.label, size: 10, stroke: 3),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: BlockText(here?.name.toUpperCase() ?? 'EMPTY',
                        size: 8,
                        stroke: 2,
                        color: here == null ? const Color(0xFF9AA0A6) : Rb.neon),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final avatar = AvatarPreview.fromData(
      {
        ...data,
        'equipped_clothes': _draft.isEmpty ? <String>[] : [_draft],
      },
      filterQuality: FilterQuality.none, // pixel-sharp
    );

    return Row(
      children: [
        SizedBox(
          width: 84,
          child: Column(children: [slot(_slots[0]), slot(_slots[1])]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Block(
              color: const Color(0xFF8FD0FF),
              edge: Colors.black,
              depth: 6,
              radius: 18,
              padding: EdgeInsets.zero,
              child: SizedBox.expand(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      BlockBackground(id: (data['background_id'] as String?) ?? 'valley'),
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 4),
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
                                  child: avatar,
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
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 84,
          child: Column(children: [slot(_slots[2]), slot(_slots[3])]),
        ),
      ],
    );
  }

  // ── equip button ─────────────────────────────────────────────────────
  Widget _equipButton(String uid, String saved) {
    final changed = _draft != saved;
    final on = changed && !_saving;
    return PressBlock(
      color: on ? Rb.neon : Rb.panel,
      edge: on ? Rb.greenEdge : Rb.panelEdge,
      depth: 8,
      radius: 16,
      padding: const EdgeInsets.symmetric(vertical: 14),
      onTap: on ? () => _equip(uid) : null,
      child: SizedBox(
        width: double.infinity,
        child: Center(
          child: BlockText(
            _saving
                ? 'SAVING…'
                : changed
                    ? '⚔️ EQUIP GEAR'
                    : '✔ GEAR EQUIPPED',
            size: 20,
            stroke: 4.5,
            color: on ? Colors.white : const Color(0xFF9AA0A6),
          ),
        ),
      ),
    );
  }

  // ── inventory ────────────────────────────────────────────────────────
  Widget _inventory(List<ShopItem> inventory) {
    final shown = _slotFilter == null
        ? inventory
        : inventory.where((i) => i.slot == _slotFilter).toList();
    final label = _slotFilter == null
        ? 'ALL'
        : _slots.firstWhere((s) => s.id == _slotFilter).label;

    return Block(
      color: Rb.panel,
      edge: Rb.panelEdge,
      depth: 6,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BlockText('🎒 INVENTORY', size: 14, stroke: 3.5),
              const Spacer(),
              BlockText(label, size: 11, stroke: 3, color: Rb.gold),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: BlockText(
                      'NOTHING FOR THIS SLOT YET.\nEarn gear on the Milestone path\nor buy it in the 🛒 Shop!',
                      size: 11,
                      stroke: 3,
                      align: TextAlign.center,
                      color: const Color(0xFFB8BDC4),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.only(bottom: 6),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: shown.length,
                    itemBuilder: (_, i) => _tile(shown[i]),
                  ),
          ),
        ],
      ),
    );
  }

  String _lockText(ShopItem item) =>
      (item.unlockKm > _totalKm || item.unlockLevel > _level)
          ? item.lockLabel(_totalKm, _level)
          : 'Buy it in the 🛒 Shop';

  Widget _tile(ShopItem item) {
    final isUnlocked = _unlocked.contains(item.id);
    final selected = isUnlocked && _draft == item.id;
    return PressBlock(
      color: selected ? const Color(0xFF1E5A3A) : Rb.slate,
      edge: selected ? Rb.greenEdge : Colors.black,
      depth: 6,
      radius: 14,
      forcePressed: selected,
      padding: const EdgeInsets.all(6),
      onTap: () {
        if (!isUnlocked) {
          _snack('🔒 ${item.name}: ${_lockText(item)}');
          return;
        }
        if (!item.equippable) {
          _snack('Art for ${item.name} is coming soon!');
          return;
        }
        // instantly shows on the central model; saved by ⚔️ EQUIP GEAR
        setState(() => _draft = selected ? '' : item.id);
      },
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black, width: 3),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.asset == null)
                      Center(child: Text(item.emoji, style: const TextStyle(fontSize: 34)))
                    else
                      ShopCropImage(
                        // the version drawn for the hero's body
                        path: clothesAssetFor(_bodyId, item.id, gender: _gender)
                                .isEmpty
                            ? item.asset!
                            : clothesAssetFor(_bodyId, item.id, gender: _gender),
                        fallbackPath: item.asset,
                        focusX: 142.5,
                        focusY: 252,
                        zoom: 0.55,
                      ),
                    if (!isUnlocked)
                      Container(
                        color: const Color(0xEE3A3D40),
                        padding: const EdgeInsets.all(3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lock, color: Colors.white, size: 22),
                            const SizedBox(height: 2),
                            BlockText(_lockText(item),
                                size: 8, stroke: 2.5, align: TextAlign.center),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: BlockText(item.name, size: 10, stroke: 3, maxLines: 1),
          ),
          const SizedBox(height: 4),
          Block(
            color: selected ? Rb.green : Rb.slot,
            edge: selected ? Rb.greenEdge : Rb.slateEdge,
            depth: 3,
            radius: 8,
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: SizedBox(
              width: double.infinity,
              child: Center(
                child: BlockText(
                  !isUnlocked
                      ? '🔒 LOCKED'
                      : !item.equippable
                      ? 'ART SOON'
                      : selected
                          ? '✔ ON MODEL'
                          : 'TAP TO WEAR',
                  size: 9,
                  stroke: 2.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
