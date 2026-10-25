import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../constants/app_icons.dart';
import '../../models/body_composition.dart';
import '../../models/character_profile.dart' show BodyTier, BodyCompositionTierX;
import '../../models/hero_items.dart';
import '../../models/hero_progress.dart';
import '../../models/hero_roster.dart';
import '../../services/sound.dart';
import '../../state/evolution_state.dart';
import '../../utils/activity_snapshot.dart';
import '../../utils/weekly.dart';
import '../../widgets/block_ui.dart';
import '../../widgets/scene_backdrop.dart';
import '../../widgets/hero_rig.dart';
import '../../widgets/pixel_icon.dart';
import '../../widgets/unlock_sheet.dart';
import '../../state/user_doc.dart';
import '../../widgets/lottie_fx.dart';

// ═════════════════════════════════════════════════════════════════
//  HERO SHOP (same layout as the old Avatar Shop)
//
//  Tabs: FEATURED, HEROES, then one tab per slot (head, face, top...).
//  Tap anything to TRY IT ON the live hero; BUY saves the look and pays for
//  whatever is not owned yet (coins).
//
//  Firestore (users/{uid}):
//    coins, total_km, xp, stage_records          currency + unlock rules
//    owned_items [id], owned_heroes [id]         bought things
//    hero_id, hero_outfit {slot: id}             the saved look
//    streak_claims [key]                         claimed streak rewards
//
//  Got three ways (see hero_items.dart / hero_roster.dart):
//    FREE (starters)  ·  EARNED (level, km, rank clear, stars)  ·  BOUGHT
// ═════════════════════════════════════════════════════════════════

/// Weekly pick discount.
const double kWeeklyDiscount = 0.25;

class _Data {
  final HeroProgress p;
  final String heroId;
  final HeroOutfit outfit;
  final Set<String> streakClaims;
  final String bg;
  const _Data(this.p, this.heroId, this.outfit, this.streakClaims, this.bg);

  factory _Data.from(Map<String, dynamic> d) => _Data(
        HeroProgress.fromData(d),
        heroIdOf(d) ?? kDefaultHeroId,
        outfitOf(d),
        d['streak_claims'] is List
            ? (d['streak_claims'] as List).whereType<String>().toSet()
            : <String>{},
        (d['background_id'] as String?) ?? 'valley',
      );
}

class _TabDef {
  final String key; // 'featured' | 'heroes' | HeroSlot.name
  final HeroSlot? slot;
  final String label;
  final Color color, edge;
  const _TabDef(this.key, this.slot, this.label, this.color, this.edge);
}

const List<_TabDef> _tabs = [
  _TabDef('featured', null, 'FEATURED', Color(0xFF7B4DFF), Color(0xFF3A1F8F)),
  _TabDef('heroes', null, 'HEROES', Color(0xFFFF7A00), Color(0xFF8F3F00)),
  _TabDef('head', HeroSlot.head, 'HEAD', Color(0xFFE5484D), Color(0xFF7A1C20)),
  _TabDef('face', HeroSlot.face, 'FACE', Color(0xFF9B59FF), Color(0xFF4B2A8A)),
  _TabDef('top', HeroSlot.top, 'TOPS', Color(0xFF00B06F), Color(0xFF006B44)),
  _TabDef('bottom', HeroSlot.bottom, 'BOTTOMS', Color(0xFF1E88E5), Color(0xFF0D47A1)),
  _TabDef('shoes', HeroSlot.shoes, 'SHOES', Color(0xFFD97706), Color(0xFF7C4A03)),
  _TabDef('back', HeroSlot.back, 'BACK', Color(0xFF0EA5A5), Color(0xFF065858)),
  _TabDef('neck', HeroSlot.neck, 'NECK', Color(0xFFE05297), Color(0xFF7A2252)),
];

class AvatarShopScreen extends StatefulWidget {
  const AvatarShopScreen({super.key});

  @override
  State<AvatarShopScreen> createState() => _AvatarShopScreenState();
}

class _AvatarShopScreenState extends State<AvatarShopScreen> {
  String _tab = 'featured';
  String _query = '';
  final TextEditingController _searchCtl = TextEditingController();
  // While searching on a phone, the preview panel is hidden so the search box
  // sits at the top and the keyboard can't cover it.
  final FocusNode _searchFocus = FocusNode();
  ActivitySnapshot _act = const ActivitySnapshot();
  bool _claiming = false;
  bool _buying = false;

  // Draft look = what the live preview shows (not saved until BUY / SAVE).
  String _sig = '';
  String _heroD = kDefaultHeroId;
  Map<String, String> _outD = <String, String>{};

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() {
      if (mounted) setState(() {});
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      ActivitySnapshot.load(uid).then((a) {
        if (mounted) setState(() => _act = a);
      });
    }
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── streak + weekly pick ──

  static const List<(int, int)> _streakRewards = [(3, 250), (7, 750), (14, 1500), (30, 4000)];

  String _streakKey(int days) {
    final st = _act.streakStart;
    if (st == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '$days:${st.year}-${two(st.month)}-${two(st.day)}';
  }

  Future<void> _claimStreak(String uid, int days, int bonus) async {
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
          'coins': FieldValue.increment(bonus),
          'streak_claims': FieldValue.arrayUnion([key]),
          'streak_claim_at': FieldValue.serverTimestamp(), // rules: 1 per day
        });
      });
      Sound.I.play(Sfx.gem);
      _snack('\u{1F525} $days-day streak reward: +$bonus \u{1FA99}');
    } catch (e) {
      _snack(e == 'claimed' ? 'Already claimed.' : 'Claim failed. Try again.');
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  /// One purchasable item is spotlighted per week (same for every player).
  HeroItem? _weeklyPick() {
    final pool = kHeroItems.where((i) => i.isForSale && i.rule.isNone).toList();
    if (pool.isEmpty) return null;
    return pool[Weekly.index(DateTime.now()) % pool.length];
  }

  /// Coin price today, with the weekly discount.
  int _price(HeroItem i) {
    final off = _weeklyPick()?.id == i.id;
    final v = i.coins;
    if (v == 0 || !off) return v;
    return (v * (1 - kWeeklyDiscount)).round().clamp(1, v).toInt();
  }

  String _priceText(HeroItem i) {
    final c = _price(i);
    if (c > 0) return '$c \u{1FA99}';
    return i.isFree ? 'FREE' : 'EARN';
  }

  // ── ownership ──

  bool _ownedItem(HeroItem i, _Data s) => isItemUnlocked(i, s.p);
  bool _ruleLockedItem(HeroItem i, _Data s) => !_ownedItem(i, s) && !i.rule.met(s.p);
  bool _ownedHero(HeroDef h, _Data s) => isHeroUnlocked(h, s.p);
  bool _ruleLockedHero(HeroDef h, _Data s) =>
      !_ownedHero(h, s) && (h.coinPrice == 0 || !h.rule.met(s.p));

  List<HeroItem> _draftItems() {
    final out = <HeroItem>[];
    for (final slot in kSlotDrawOrder) {
      final id = _outD[slot.name];
      if (id == null) continue;
      final it = heroItemById(id);
      if (it != null) out.add(it);
    }
    return out;
  }

  int _cost(_Data s) {
    var coins = 0;
    for (final i in _draftItems()) {
      if (_ownedItem(i, s)) continue;
      coins += _price(i);
    }
    final h = heroById(_heroD);
    if (h != null && !_ownedHero(h, s)) coins += h.coinPrice;
    return coins;
  }

  bool _changed(_Data s) {
    if (_heroD != s.heroId) return true;
    if (_outD.length != s.outfit.length) return true;
    for (final e in _outD.entries) {
      if (s.outfit[e.key] != e.value) return true;
    }
    return false;
  }

  /// Opens the "how to unlock" pop-up for the first locked thing in the draft.
  void _openLockedDraft(_Data s) {
    final h = heroById(_heroD);
    if (h != null && _ruleLockedHero(h, s)) {
      _openHeroSheet(h, s);
      return;
    }
    for (final i in _draftItems()) {
      if (_ruleLockedItem(i, s)) {
        _openItemSheet(i, s);
        return;
      }
    }
  }

  /// Name of a previewed thing the player cannot get yet (rank / level locked).
  String? _lockedInDraft(_Data s) {
    final h = heroById(_heroD);
    if (h != null && _ruleLockedHero(h, s)) return h.name;
    for (final i in _draftItems()) {
      if (_ruleLockedItem(i, s)) return i.name;
    }
    return null;
  }

  String _fmt(int n) => n
      .toString()
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  /// Gear is drawn on the human hero only; costume heroes wear their own outfit.
  void _costumeNotice() {
    showInfoSheet(
      context,
      title: 'COSTUMES CAN\'T WEAR GEAR',
      message:
          '${heroById(_heroD)?.name ?? 'This costume'} comes with its own outfit, so shop gear can only be worn by SPROUT, your main hero. Switch to SPROUT to try gear on.',
      art: HeroStill(heroId: _heroD, tier: BodyTier.normal),
      actionLabel: 'SWITCH TO SPROUT',
      onAction: () => setState(() => _heroD = kDefaultHeroId),
    );
  }

  /// Changing hero asks "are you sure?" first; other saves go straight through.
  void _askThenSave(String uid, _Data s) {
    if (_heroD == s.heroId) {
      _purchase(uid);
      return;
    }
    final nh = heroById(_heroD);
    final oh = heroById(s.heroId);
    showConfirmSheet(
      context,
      title: 'CHANGE COSTUME?',
      message: 'Switch from ${oh?.name ?? 'your look'} to ${nh?.name ?? 'this costume'}? '
          '${(nh?.costume ?? false) && !(oh?.costume ?? false) ? '${nh!.name} wears its own outfit, so your shop gear stays saved for SPROUT. ' : ''}'
          'You can switch back any time.',
      art: HeroStill(heroId: _heroD, tier: BodyTier.normal),
      confirmLabel: 'YES, CHANGE',
      onConfirm: () => _purchase(uid),
    );
  }

  void _openHeroSheet(HeroDef h, _Data s) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final goalsDone = h.rule.met(s.p);
    final price = h.coinPrice > 0 ? '${h.coinPrice} \u{1FA99}' : null;
    showUnlockSheet(
      context,
      title: h.name,
      kind: h.id == kDefaultHeroId ? 'MAIN HERO' : '${h.rarityLabel} COSTUME',
      art: HeroStill(heroId: h.id, tier: BodyTier.normal),
      reqs: [
        ...unlockReqs(h.rule, s.p),
        if (price != null)
          UnlockReq('Get ${h.coinPrice} \u{1FA99} coins',
              progress: '${s.p.coins} / ${h.coinPrice}',
              fraction: (s.p.coins / h.coinPrice).clamp(0.0, 1.0),
              done: s.p.coins >= h.coinPrice),
      ],
      priceLabel: price,
      youHave: price == null ? null : 'You have ${_fmt(s.p.coins)} \u{1FA99}',
      tip: unlockTip(h.rule, s.p) ??
          (price != null && s.p.coins < h.coinPrice
              ? 'Coins come from every run, daily quests, rank clears and stars.'
              : null),
      canBuy: uid != null && goalsDone && s.p.coins >= h.coinPrice && h.coinPrice > 0,
      onBuy: uid == null
          ? null
          : () {
              setState(() => _heroD = h.id);
              _askThenSave(uid, s);
            },
      accent: h.color,
      accentEdge: h.edge,
    );
  }

  void _openItemSheet(HeroItem i, _Data s) {
    showUnlockSheet(
      context,
      title: i.name,
      kind: '${_rarity(i.rarity).label} ${i.slot.label} ITEM',
      art: ItemCrop(item: i, heroId: kDefaultHeroId, tier: BodyTier.normal),
      reqs: unlockReqs(i.rule, s.p),
      priceLabel: i.isForSale ? _priceText(i) : null,
      youHave: !i.isForSale ? null : 'You have ${_fmt(s.p.coins)} \u{1FA99}',
      tip: unlockTip(i.rule, s.p),
    );
  }

  // ── ONE ITEM AT A TIME ──
  // The shop sells one thing per purchase. Owned gear can be mixed freely,
  // but trying on something NOT owned puts back any other not-owned thing
  // you were previewing, so BUY is always for exactly one item or hero.

  /// Puts every not-owned item in the draft back to the saved look.
  /// Returns the names of what was taken off.
  List<String> _dropUnownedItems(_Data s, {String? exceptSlot}) {
    final dropped = <String>[];
    final next = Map<String, String>.of(_outD);
    for (final e in _outD.entries) {
      if (e.key == exceptSlot) continue;
      final it = heroItemById(e.value);
      if (it == null || _ownedItem(it, s)) continue;
      dropped.add(it.name);
      final saved = s.outfit[e.key];
      if (saved != null) {
        next[e.key] = saved;
      } else {
        next.remove(e.key);
      }
    }
    _outD = next;
    return dropped;
  }

  void _oneAtATimeNotice(List<String> dropped) {
    if (dropped.isEmpty) return;
    _snack('One item at a time: took off ${dropped.join(', ')}');
  }

  void _onItemTap(HeroItem item, _Data s) {
    _searchFocus.unfocus(); // show the preview again with the item on
    if (heroIsCostume(_heroD)) {
      if (_ruleLockedItem(item, s)) {
        _openItemSheet(item, s);
      } else {
        _costumeNotice();
      }
      return;
    }
    if (_ruleLockedItem(item, s)) {
      _openItemSheet(item, s); // how to unlock it (you can still try it on)
    }
    final dropped = <String>[];
    setState(() {
      if (_outD[item.slot.name] == item.id) {
        _outD = Map<String, String>.of(_outD)..remove(item.slot.name);
      } else {
        if (!_ownedItem(item, s)) {
          dropped.addAll(_dropUnownedItems(s, exceptSlot: item.slot.name));
          final h = heroById(_heroD);
          if (h != null && !_ownedHero(h, s)) {
            dropped.add(h.name);
            _heroD = heroIsCostume(s.heroId) ? kDefaultHeroId : s.heroId;
          }
        }
        _outD = Map<String, String>.of(_outD)..[item.slot.name] = item.id;
      }
    });
    _oneAtATimeNotice(dropped);
  }

  void _onHeroTap(HeroDef h, _Data s) {
    _searchFocus.unfocus();
    if (_ruleLockedHero(h, s)) {
      _openHeroSheet(h, s); // how to unlock it (you can still look at it)
    }
    final dropped = <String>[];
    setState(() {
      if (!_ownedHero(h, s)) dropped.addAll(_dropUnownedItems(s));
      _heroD = h.id;
    });
    _oneAtATimeNotice(dropped);
  }

  Future<void> _purchase(String uid) async {
    setState(() => _buying = true);
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final snap = await txn.get(ref);
        final fresh = _Data.from(snap.data() ?? <String, dynamic>{});

        var coins = 0;
        final newItems = <String>[];
        for (final i in _draftItems()) {
          if (_ownedItem(i, fresh)) continue;
          if (_ruleLockedItem(i, fresh)) throw 'locked';
          coins += _price(i);
          newItems.add(i.id);
        }
        final h = heroById(_heroD);
        String? newHero;
        if (h != null && !_ownedHero(h, fresh)) {
          if (_ruleLockedHero(h, fresh)) throw 'locked';
          coins += h.coinPrice;
          newHero = h.id;
        }
        if (fresh.p.coins < coins) throw 'coins';

        final up = <String, dynamic>{
          'hero_id': _heroD,
          'hero_outfit': Map<String, String>.of(_outD),
        };
        if (coins > 0) up['coins'] = FieldValue.increment(-coins);
        if (newItems.isNotEmpty) up['owned_items'] = FieldValue.arrayUnion(newItems);
        if (newHero != null) up['owned_heroes'] = FieldValue.arrayUnion([newHero]);
        txn.update(ref, up);
      });
      Sound.I.play(Sfx.buy);
      _snack('✅ Look saved!');
    } catch (e) {
      Sound.I.play(Sfx.error);
      _snack(e == 'coins'
              ? 'Not enough coins!'
              : e == 'locked'
                  ? 'Something is still locked.'
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
        body: LoadingRunner(),
      );
    }

    return Scaffold(
      backgroundColor: Rb.bg,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: UserDoc.instance.stream,
          initialData: UserDoc.instance.snapshotFor(uid),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const LoadingRunner();
            }
            final s = _Data.from(snap.data!.data() ?? <String, dynamic>{});

            // (Re)load the draft whenever the SAVED look changes.
            final keys = s.outfit.keys.toList()..sort();
            final sig = '${s.heroId}|${keys.map((k) => '$k=${s.outfit[k]}').join(',')}';
            if (sig != _sig) {
              _sig = sig;
              _heroD = s.heroId;
              _outD = Map<String, String>.of(s.outfit);
            }

            return ValueListenableBuilder<BodyCompositionState>(
              valueListenable: EvolutionState.instance.composition,
              builder: (context, form, _) =>
                  _layout(context, s, uid, form.tier),
            );
          },
        ),
      ),
    );
  }

  Widget _layout(BuildContext context, _Data s, String uid, BodyTier tier) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 760;
      final browse = Column(
        children: [
          _buildSearchRow(),
          const SizedBox(height: 8),
          _buildPills(),
          const SizedBox(height: 10),
          Expanded(child: _buildContent(s, tier)),
        ],
      );

      if (wide) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 290,
                child: SingleChildScrollView(
                  child: _buildPreviewPanel(s, uid, tier, wide: true),
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

      final searching = _searchFocus.hasFocus;
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Column(
          children: [
            if (!searching) ...[
              _buildHeader(s),
              const SizedBox(height: 8),
              _buildPreviewPanel(s, uid, tier, wide: false),
              const SizedBox(height: 4),
            ],
            Expanded(child: browse),
          ],
        ),
      );
    });
  }

  // ───────────────────────── header ─────────────────────────

  Widget _buildHeader(_Data s) {
    Widget chip(String text, Color c, Color e) => Block(
          color: c,
          edge: e,
          depth: 3,
          radius: 10,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: BlockText(text, size: 10.5, stroke: 3),
        );

    return Block(
      color: Rb.hud,
      edge: Rb.hudEdge,
      depth: 5,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          const Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: IconLabel(
                iconPath: AppIcons.shopChest,
                iconSize: 26,
                gap: 8,
                label: BlockText('HERO SHOP', size: 18, stroke: 4),
              ),
            ),
          ),
          const SizedBox(width: 6),
          chip('LV ${s.p.level}', Rb.green, Rb.greenEdge),
          const SizedBox(width: 5),
          chip('\u{1FA99} ${_fmt(s.p.coins)}', Rb.orange, Rb.orangeEdge),
        ],
      ),
    );
  }

  // ───────────────────────── search + pills ─────────────────────────

  Widget _buildSearchRow() {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Rb.panel,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(0, 3), blurRadius: 0),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtl,
              focusNode: _searchFocus,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              onSubmitted: (_) => _searchFocus.unfocus(),
              textInputAction: TextInputAction.search,
              autocorrect: false,
              textAlignVertical: TextAlignVertical.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  height: 1.2),
              cursorColor: Rb.neon,
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.symmetric(vertical: 6),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Search costumes and items',
                hintStyle: TextStyle(
                    color: Colors.white38,
                    fontWeight: FontWeight.w800,
                    fontSize: 14),
              ),
            ),
          ),
          if (_query.isNotEmpty || _searchFocus.hasFocus)
            GestureDetector(
              onTap: () => setState(() {
                _query = '';
                _searchCtl.clear();
                _searchFocus.unfocus();
              }),
              child: const Icon(Icons.close, color: Colors.white70, size: 18),
            ),
        ],
      ),
    );
  }

  Widget _buildPills() {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 4),
        itemCount: _tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (_, i) {
          final t = _tabs[i];
          final sel = _tab == t.key;
          return PressBlock(
            color: t.color,
            edge: t.edge,
            depth: 3,
            radius: 18,
            forcePressed: sel,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
            onTap: () => setState(() => _tab = t.key),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BlockText(t.label, size: 11.5, stroke: 3),
                const SizedBox(height: 1),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 3,
                  width: sel ? 24 : 0,
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

  // ───────────────────────── content ─────────────────────────

  // ── search ──
  // Searches EVERY category (whatever tab is open). Case, spaces and symbols
  // are ignored, so even one letter lists everything that contains it.
  // Best matches first:
  //   whole name > name starts with it > a word starts with it >
  //   anywhere in the name > category / rarity / price words > letters in
  //   order (typo-friendly, "rdcp" finds Red Cap).
  // Several words ("gold head") must ALL match.

  static String _norm(String v) =>
      v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static int _scoreWord(String q, String name, List<String> tags) {
    final n = _norm(name);
    if (q.isEmpty || n.isEmpty) return 0;
    if (n == q) return 1000;
    if (n.startsWith(q)) return 900 - n.length;
    final words = name
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.isNotEmpty);
    if (words.any((w) => w.startsWith(q))) return 800 - n.length;
    final at = n.indexOf(q);
    if (at >= 0) return 700 - at * 5 - n.length;
    // one letter: names only (every category word would match otherwise)
    if (q.length < 2) return 0;
    for (final t in tags) {
      if (_norm(t).contains(q)) return 500;
    }
    if (q.length >= 2) {
      var i = 0;
      for (var k = 0; k < n.length && i < q.length; k++) {
        if (n[k] == q[i]) i++;
      }
      if (i == q.length) return 300 - n.length;
    }
    return 0;
  }

  /// 0 = no match. Every word of the query has to match something.
  static int _score(String query, String name, List<String> tags) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map(_norm)
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return 0;
    var total = 0;
    for (final w in words) {
      final sc = _scoreWord(w, name, tags);
      if (sc == 0) return 0;
      total += sc;
    }
    return total;
  }

  List<String> _itemTags(HeroItem i) {
    final r = _rarity(i.rarity).label;
    final tab = _tabs.where((t) => t.slot == i.slot);
    return [
      i.slot.label,
      if (tab.isNotEmpty) tab.first.label,
      r,
      if (r == 'LEGEND') 'legendary',
      'item',
      _priceText(i),
      if (i.rule.label != null) i.rule.label!,
    ];
  }

  List<String> _heroTags(HeroDef h) => [
        'hero',
        'heroes',
        h.costume ? 'costume' : 'main hero',
        h.rarityLabel,
        h.tagline,
        if (h.coinPrice > 0) '${h.coinPrice}' else (h.starter ? 'free' : 'earn'),
      ];

  Widget _buildContent(_Data s, BodyTier tier) {
    if (_query.isNotEmpty) {
      final hs = <(HeroDef, int)>[
        for (final h in kHeroes)
          if (_score(_query, h.name, _heroTags(h)) case final sc when sc > 0)
            (h, sc),
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      final its = <(HeroItem, int)>[
        for (final i in kHeroItems)
          if (_score(_query, i.name, _itemTags(i)) case final sc when sc > 0)
            (i, sc),
      ]..sort((a, b) {
          final c = b.$2.compareTo(a.$2);
          return c != 0 ? c : a.$1.coins.compareTo(b.$1.coins);
        });
      final total = hs.length + its.length;
      if (total == 0) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: BlockText('NOTHING FOUND FOR "${_query.toUpperCase()}"',
                size: 14, stroke: 3.5, align: TextAlign.center),
          ),
        );
      }
      // the better matches come first, heroes or items
      final heroesFirst =
          hs.isNotEmpty && (its.isEmpty || hs.first.$2 >= its.first.$2);
      final heroes = [for (final e in hs) e.$1];
      final items = [for (final e in its) e.$1];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: BlockText(
              '$total RESULT${total == 1 ? '' : 'S'} FOR "${_query.toUpperCase()}"  •  ALL CATEGORIES',
              size: 10.5,
              stroke: 2.5,
              color: const Color(0xFFB8BDC4),
            ),
          ),
          Expanded(
            child: heroesFirst
                ? _buildGrid(s, tier, heroes: heroes, items: items)
                : _buildMixedGrid(s, tier, items: items, heroes: heroes),
          ),
        ],
      );
    }
    if (_tab == 'featured') return _buildFeatured(s, tier);
    if (_tab == 'heroes') return _buildGrid(s, tier, heroes: kHeroes, items: const []);
    final slot = _tabs.firstWhere((t) => t.key == _tab).slot!;
    return _buildGrid(s, tier, heroes: const [], items: heroItemsIn(slot));
  }

  /// Same grid, items before heroes (when an item is the best match).
  Widget _buildMixedGrid(_Data s, BodyTier tier,
      {required List<HeroItem> items, required List<HeroDef> heroes}) {
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / 130).floor().clamp(3, 6);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 9,
          mainAxisSpacing: 6,
          childAspectRatio: 0.7,
        ),
        itemCount: items.length + heroes.length,
        itemBuilder: (context, i) => i < items.length
            ? _itemTile(items[i], s, tier)
            : _heroTile(heroes[i - items.length], s, tier),
      );
    });
  }

  Widget _buildGrid(_Data s, BodyTier tier,
      {required List<HeroDef> heroes, required List<HeroItem> items}) {
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / 130).floor().clamp(3, 6);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 9,
          mainAxisSpacing: 6,
          childAspectRatio: 0.7,
        ),
        itemCount: heroes.length + items.length,
        itemBuilder: (context, i) => i < heroes.length
            ? _heroTile(heroes[i], s, tier)
            : _itemTile(items[i - heroes.length], s, tier),
      );
    });
  }

  // ── Featured ──

  int _xpForLevel(int level) => 500 * (level - 1) * level ~/ 2;

  double _progress(UnlockRule r, HeroProgress p) {
    var v = 1.0;
    void minWith(double x) {
      if (x < v) v = x;
    }
    if (r.level > 1) minWith(p.xp / _xpForLevel(r.level));
    if (r.km > 0) minWith(p.totalKm / r.km);
    if (r.stars > 0) minWith(p.totalStars / r.stars);
    if (r.stageId != null) minWith(p.cleared(r.stageId!) ? 1.0 : 0.0);
    return v.clamp(0.0, 1.0).toDouble();
  }

  String _remaining(UnlockRule r, HeroProgress p) {
    final parts = <String>[];
    if (r.km > p.totalKm) parts.add('${(r.km - p.totalKm).toStringAsFixed(1)} km to go');
    if (r.level > p.level) {
      final xp = _xpForLevel(r.level) - p.xp;
      parts.add('${_fmt(xp < 0 ? 0 : xp)} XP to go');
    }
    if (r.stars > p.totalStars) parts.add('${r.stars - p.totalStars} stars to go');
    if (r.stageId != null && !p.cleared(r.stageId!)) parts.add(r.label ?? 'Clear the rank');
    return parts.join('  •  ');
  }

  Widget _buildFeatured(_Data s, BodyTier tier) {
    // everything still locked behind a rule, closest first
    final gated = <({String name, Widget art, UnlockRule rule})>[];
    for (final h in kHeroes) {
      if (_ruleLockedHero(h, s)) {
        gated.add((name: h.name, art: _heroArt(h, tier), rule: h.rule));
      }
    }
    for (final i in kHeroItems) {
      if (_ruleLockedItem(i, s) && i.isEarned) {
        gated.add((name: i.name, art: _itemArt(i, tier), rule: i.rule));
      }
    }
    gated.sort((a, b) => _progress(b.rule, s.p).compareTo(_progress(a.rule, s.p)));
    final next = gated.isEmpty ? null : gated.first;

    return LayoutBuilder(builder: (context, c) {
      final tileW = (c.maxWidth - 4 - 10) / 2;
      return ListView(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 16),
        children: [
          _streakCard(s),
          const SizedBox(height: 10),
          if (_weeklyPick() case final pick?) ...[
            _weeklyPickCard(pick, s, tier),
            const SizedBox(height: 10),
          ],
          if (next != null) _nextUnlockCard(next, s),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              for (final t in _tabs.where((t) => t.key != 'featured'))
                SizedBox(width: tileW, child: _categoryTile(t, s, tier)),
            ],
          ),
          if (gated.length > 1) ...[
            const SizedBox(height: 10),
            const BlockText('EARN TO UNLOCK', size: 13, stroke: 3.5, color: Rb.gold),
            const SizedBox(height: 8),
            for (final g in gated.skip(1)) _unlockRow(g, s),
          ],
        ],
      );
    });
  }

  Widget _streakCard(_Data s) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final days = _act.streakDays;
    return Block(
      color: const Color(0xFFB5400A),
      edge: const Color(0xFF5A1F00),
      depth: 5,
      radius: 16,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BlockText('\u{1F525} $days-DAY STREAK', size: 14, stroke: 4),
              const Spacer(),
              const BlockText('run daily for coins', size: 9, stroke: 2.5),
            ],
          ),
          const SizedBox(height: 7),
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

  Widget _streakChip(String? uid, _Data s, int need, int bonus, int days) {
    final key = _streakKey(need);
    final claimed = key.isNotEmpty && s.streakClaims.contains(key);
    final ready = days >= need && !claimed && uid != null;
    final Color c = claimed ? Rb.panel : (ready ? Rb.green : Rb.slate);
    final Color e = claimed ? Rb.panelEdge : (ready ? Rb.greenEdge : Rb.slateEdge);
    return PressBlock(
      color: c,
      edge: e,
      depth: 3,
      radius: 11,
      forcePressed: claimed,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      onTap: ready && !_claiming ? () => _claimStreak(uid, need, bonus) : null,
      child: Column(
        children: [
          BlockText('${need}D', size: 11.5, stroke: 3.5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: BlockText(
              claimed ? '✔' : '\u{1FA99}$bonus',
              size: 10.5,
              stroke: 3,
              color: claimed ? Rb.neon : (ready ? Colors.white : Rb.gold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weeklyPickCard(HeroItem i, _Data s, BodyTier tier) {
    final owned = _ownedItem(i, s);
    return PressBlock(
      color: const Color(0xFF5B3A9E),
      edge: const Color(0xFF2A1A52),
      depth: 5,
      radius: 16,
      padding: const EdgeInsets.all(10),
      onTap: () => _onItemTap(i, s),
      child: Row(
        children: [
          SizedBox(width: 70, height: 70, child: _itemArt(i, tier)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BlockText('⭐ WEEKLY PICK', size: 10.5, stroke: 3, color: Rb.gold),
                    const Spacer(),
                    BlockText(Weekly.countdown(DateTime.now()), size: 9, stroke: 2.5),
                  ],
                ),
                const SizedBox(height: 2),
                BlockText(i.name, size: 16, stroke: 4, maxLines: 1),
                const SizedBox(height: 5),
                BlockText(
                  owned
                      ? '✔ OWNED'
                      : '${_priceText(i)}  •  25% off, tap to try on',
                  size: 10.5,
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

  Widget _nextUnlockCard(({String name, Widget art, UnlockRule rule}) g, _Data s) {
    return Block(
      color: const Color(0xFFB8860B),
      edge: const Color(0xFF5A4305),
      depth: 5,
      radius: 16,
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          SizedBox(width: 70, height: 70, child: g.art),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BlockText('NEXT UNLOCK', size: 10.5, stroke: 3),
                const SizedBox(height: 2),
                BlockText(g.name, size: 16, stroke: 4, maxLines: 1),
                const SizedBox(height: 6),
                BlockBar(value: _progress(g.rule, s.p), height: 12, color: Rb.neon),
                const SizedBox(height: 3),
                BlockText(_remaining(g.rule, s.p), size: 9.5, stroke: 2.5),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _unlockRow(({String name, Widget art, UnlockRule rule}) g, _Data s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Block(
        color: Rb.slate,
        edge: Rb.slateEdge,
        depth: 4,
        radius: 13,
        padding: const EdgeInsets.all(7),
        child: Row(
          children: [
            SizedBox(width: 46, height: 46, child: g.art),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BlockText(g.name, size: 12.5, stroke: 3, maxLines: 1),
                  const SizedBox(height: 4),
                  BlockBar(value: _progress(g.rule, s.p), height: 8, color: Rb.green),
                  const SizedBox(height: 3),
                  BlockText(_remaining(g.rule, s.p),
                      size: 9, stroke: 2.5, color: const Color(0xFFB8BDC4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryTile(_TabDef t, _Data s, BodyTier tier) {
    final isHeroes = t.key == 'heroes';
    final items = isHeroes ? const <HeroItem>[] : heroItemsIn(t.slot!);
    final total = isHeroes ? kHeroes.length : items.length;
    final owned = isHeroes
        ? kHeroes.where((h) => _ownedHero(h, s)).length
        : items.where((i) => _ownedItem(i, s)).length;
    final arts = <Widget>[
      if (isHeroes)
        for (final h in kHeroes.take(2)) _heroArt(h, tier)
      else
        for (final i in items.take(2)) _itemArt(i, tier),
    ];
    return PressBlock(
      color: t.color,
      edge: t.edge,
      depth: 5,
      radius: 15,
      padding: const EdgeInsets.all(9),
      onTap: () => setState(() => _tab = t.key),
      child: SizedBox(
        height: 96,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BlockText(t.label, size: 13, stroke: 3.5),
            const SizedBox(height: 5),
            Expanded(
              child: Row(
                children: [
                  for (final a in arts)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: a,
                      ),
                    ),
                  if (arts.isEmpty) const Spacer(),
                ],
              ),
            ),
            const SizedBox(height: 5),
            BlockText('$owned / $total OWNED', size: 9, stroke: 2.5),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── tiles ─────────────────────────

  Widget _frame(Widget child, {Color bg = const Color(0xFFCBD5E1)}) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black, width: 3),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(7), child: child),
      );

  Widget _itemArt(HeroItem i, BodyTier tier) =>
      _frame(ItemCrop(
          item: i,
          heroId: heroIsCostume(_heroD) ? kDefaultHeroId : _heroD,
          tier: tier));

  Widget _heroArt(HeroDef h, BodyTier tier) => _frame(
        Padding(
          padding: const EdgeInsets.all(3),
          child: HeroStill(heroId: h.id, tier: tier),
        ),
        bg: h.color.withValues(alpha: 0.55),
      );

  ({Color c, Color e, String label}) _rarity(int r) {
    switch (r) {
      case 3:
        return (c: const Color(0xFF9A6B00), e: const Color(0xFF4A3300), label: 'LEGEND');
      case 2:
        return (c: const Color(0xFF5B3A9E), e: const Color(0xFF2A1A52), label: 'EPIC');
      case 1:
        return (c: const Color(0xFF1E5F8F), e: const Color(0xFF0A2B45), label: 'RARE');
      default:
        return (c: Rb.slate, e: Colors.black, label: 'COMMON');
    }
  }

  Widget _tile({
    required Widget art,
    required String name,
    required ({Color c, Color e, String label}) r,
    required bool equipped,
    required bool owned,
    required bool locked,
    required String? lockText,
    required double? lockProgress,
    required String priceText,
    required VoidCallback onTap,
  }) {
    return PressBlock(
      color: equipped ? const Color(0xFF1E4A66) : r.c,
      edge: equipped ? Rb.neon : r.e,
      depth: 5,
      radius: 13,
      forcePressed: equipped,
      padding: const EdgeInsets.all(5),
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  art,
                  if (locked)
                    Container(
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xDD3A3D40),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: 90,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const PixelIcon(AppIcons.lock, size: 20),
                              const SizedBox(height: 2),
                              BlockText(lockText ?? 'Locked',
                                  size: 8, stroke: 2.5, align: TextAlign.center),
                              if (lockProgress != null) ...[
                                const SizedBox(height: 4),
                                BlockBar(value: lockProgress, height: 6, color: Rb.neon),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (!locked && r.label != 'COMMON')
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Container(
                        margin: const EdgeInsets.all(5),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
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
                        margin: const EdgeInsets.all(5),
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Rb.green,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: const Icon(Icons.check, color: Colors.white, size: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: BlockText(name, size: 10.5, stroke: 3, maxLines: 1),
          ),
          const SizedBox(height: 5),
          _tag(owned: owned, locked: locked, equipped: equipped, price: priceText),
        ],
      ),
    );
  }

  Widget _tag(
      {required bool owned,
      required bool locked,
      required bool equipped,
      required String price}) {
    Color fill, edge;
    String text;
    if (locked) {
      fill = Rb.panel;
      edge = Rb.panelEdge;
      text = '\u{1F512} LOCKED';
    } else if (equipped && owned) {
      fill = Rb.green;
      edge = Rb.greenEdge;
      text = '✔ WORN';
    } else if (owned) {
      fill = Rb.slot;
      edge = Rb.slateEdge;
      text = 'OWNED';
    } else if (price == 'FREE') {
      fill = Rb.neon;
      edge = Rb.greenEdge;
      text = 'FREE';
    } else {
      fill = Rb.green;
      edge = Rb.greenEdge;
      text = price;
    }
    return Block(
      color: fill,
      edge: edge,
      depth: 3,
      radius: 8,
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: SizedBox(
        width: double.infinity,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: BlockText(text, size: 11, stroke: 3),
          ),
        ),
      ),
    );
  }

  Widget _itemTile(HeroItem i, _Data s, BodyTier tier) {
    final owned = _ownedItem(i, s);
    final locked = _ruleLockedItem(i, s);
    return _tile(
      art: _itemArt(i, tier),
      name: i.name,
      r: _rarity(i.rarity),
      equipped: _outD[i.slot.name] == i.id,
      owned: owned,
      locked: locked,
      lockText: i.rule.label,
      lockProgress: locked ? _progress(i.rule, s.p) : null,
      priceText: _priceText(i),
      onTap: () => _onItemTap(i, s),
    );
  }

  Widget _heroTile(HeroDef h, _Data s, BodyTier tier) {
    final owned = _ownedHero(h, s);
    final locked = _ruleLockedHero(h, s);
    final price = h.coinPrice > 0 ? '${h.coinPrice} \u{1FA99}' : (h.starter ? 'FREE' : 'EARN');
    return _tile(
      art: _heroArt(h, tier),
      name: h.name,
      r: _rarity(h.rarity <= 1 ? 0 : h.rarity - 1),
      equipped: _heroD == h.id,
      owned: owned,
      locked: locked,
      lockText: h.rule.label,
      lockProgress: locked ? _progress(h.rule, s.p) : null,
      priceText: price,
      onTap: () => _onHeroTap(h, s),
    );
  }

  // ───────────────────────── preview panel ─────────────────────────

  Widget _buildPreviewPanel(_Data s, String uid, BodyTier tier, {required bool wide}) {
    final items = _draftItems();
    final cost = _cost(s);

    if (wide) {
      return Block(
        color: Rb.slate,
        edge: Rb.slateEdge,
        depth: 5,
        radius: 16,
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            _buildLiveHero(s, tier, width: double.infinity, height: 250),
            const SizedBox(height: 8),
            _buildSummary(items, cost, s, height: 96),
            const SizedBox(height: 8),
            _buildActionRow(s, uid),
          ],
        ),
      );
    }

    return Block(
      color: Rb.slate,
      edge: Rb.slateEdge,
      depth: 5,
      radius: 16,
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLiveHero(s, tier, width: 96, height: 150),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                _buildSummary(items, cost, s, height: 78),
                const SizedBox(height: 6),
                _buildActionRow(s, uid),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Name of the one not-owned thing in the draft (what BUY pays for).
  String? _buyingName(_Data s) {
    final h = heroById(_heroD);
    if (h != null && !_ownedHero(h, s)) return h.name;
    for (final i in _draftItems()) {
      if (!_ownedItem(i, s)) return i.name;
    }
    return null;
  }

  String _costText(int c) => c > 0 ? '${_fmt(c)} \u{1FA99}' : '0';

  Widget _buildActionRow(_Data s, String uid) {
    final cost = _cost(s);
    final changed = _changed(s);
    final needCoins = cost - s.p.coins;
    final broke = needCoins > 0;
    final lockedName = _lockedInDraft(s);

    String label;
    String? sub;
    Color fill = Rb.green, edge = Rb.greenEdge;
    VoidCallback? onTap;
    if (_buying) {
      label = 'SAVING…';
      fill = Rb.panel;
      edge = Rb.panelEdge;
    } else if (lockedName != null) {
      label = '\u{1F512} LOCKED';
      sub = 'Tap to see how to unlock $lockedName';
      fill = const Color(0xFF4A4F55);
      edge = Rb.panelEdge;
      onTap = () => _openLockedDraft(s);
    } else if (!changed) {
      label = 'SAVED';
      sub = 'Tap to try on';
      fill = Rb.panel;
      edge = Rb.panelEdge;
    } else if (broke) {
      label = 'NEED ${_fmt(needCoins)} \u{1FA99}';
      sub = 'Tap to see how to get more';
      fill = Rb.red;
      edge = Rb.redEdge;
      onTap = () => showNeedMoreSheet(
            context,
            what: 'YOUR LOOK',
            needCoins: cost,
            haveCoins: s.p.coins,
          );
    } else if (cost == 0) {
      label = 'SAVE';
      sub = 'Wear this look';
      onTap = () => _askThenSave(uid, s);
    } else {
      label = 'BUY';
      final what = _buyingName(s);
      sub = what == null ? _costText(cost) : '$what • ${_costText(cost)}';
      onTap = () => _askThenSave(uid, s);
    }

    return Row(
      children: [
        Expanded(
          flex: 4,
          child: PressBlock(
            color: changed && !_buying ? Rb.red : Rb.panel,
            edge: changed && !_buying ? Rb.redEdge : Rb.panelEdge,
            depth: 4,
            radius: 16,
            padding: const EdgeInsets.symmetric(vertical: 9),
            onTap: changed && !_buying
                ? () => setState(() {
                      _heroD = s.heroId;
                      _outD = Map<String, String>.of(s.outfit);
                    })
                : null,
            child: const Center(child: BlockText('CANCEL', size: 12, stroke: 3)),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 5,
          child: PressBlock(
            color: fill,
            edge: edge,
            depth: 4,
            radius: 16,
            padding: const EdgeInsets.symmetric(vertical: 5),
            onTap: onTap,
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: BlockText(label, size: 13, stroke: 3.5),
                  ),
                  if (sub != null)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: BlockText(sub, size: 9, stroke: 2.5),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The hero, moving, wearing the draft look, on the chosen background.
  Widget _buildLiveHero(_Data s, BodyTier tier,
      {required double width, required double height}) {
    return Block(
      color: const Color(0xFF8FD0FF),
      edge: Colors.black,
      depth: 3,
      radius: 12,
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const SceneBackdrop(),
              Padding(
                padding: EdgeInsets.only(
                    top: 6, bottom: height * SceneBackdrop.grassFraction),
                child: Center(
                  child: HeroRig(
                    heroId: _heroD,
                    tier: tier,
                    pose: RigPose.idle,
                    height: height * (1 - SceneBackdrop.grassFraction) - 8,
                    outfit: _outD,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummary(List<HeroItem> items, int cost, _Data s,
      {required double height}) {
    final hero = heroById(_heroD);
    return Block(
      color: Rb.panel,
      edge: Rb.panelEdge,
      depth: 3,
      radius: 12,
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (hero != null)
                    _sumRow(const PixelIcon(AppIcons.hero, size: 16), hero.name,
                        _ownedHero(hero, s) ? 'OWNED' : '${hero.coinPrice} \u{1FA99}',
                        _ownedHero(hero, s)),
                  for (final i in items)
                    _sumRow(PixelIcon(i.iconPath, size: 16), i.name,
                        _ownedItem(i, s) ? 'OWNED' : _priceText(i), _ownedItem(i, s)),
                ],
              ),
            ),
            const Divider(color: Colors.black54, thickness: 2, height: 6),
            Row(
              children: [
                const BlockText('TOTAL', size: 10.5, stroke: 3),
                const Spacer(),
                BlockText(_costText(cost), size: 11.5, stroke: 3, color: Rb.gold),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sumRow(Widget icon, String name, String right, bool owned) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              right,
              style: TextStyle(
                  color: owned ? Rb.neon : Rb.gold,
                  fontSize: 10,
                  fontWeight: FontWeight.w900),
            ),
          ],
        ),
      );
}

/// Close-up of one item worn by a hero, for shop and wardrobe cards.
/// Shows part of the 286x512 hero picture, centred on where the item sits.
class ItemCrop extends StatelessWidget {
  final HeroItem item;
  final String heroId;
  final BodyTier tier;
  const ItemCrop({
    super.key,
    required this.item,
    required this.heroId,
    required this.tier,
  });

  /// (focusX, focusY, zoom) in canvas pixels, per slot.
  static (double, double, double) _focus(HeroSlot s) {
    switch (s) {
      case HeroSlot.head:
        return (143, 150, 1.6);
      case HeroSlot.face:
        return (143, 178, 2.0);
      case HeroSlot.top:
        return (143, 272, 1.7);
      case HeroSlot.neck:
        return (143, 240, 1.9);
      case HeroSlot.bottom:
        return (143, 392, 1.7);
      case HeroSlot.shoes:
        return (143, 462, 2.0);
      case HeroSlot.back:
        return (143, 290, 1.1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (fx, fy, zoom) = _focus(item.slot);
    return LayoutBuilder(builder: (context, c) {
      final z = zoom * c.maxWidth / kHeroW;
      return ClipRect(
        child: Stack(
          children: [
            Positioned(
              left: c.maxWidth / 2 - fx * z,
              top: c.maxHeight / 2 - fy * z,
              width: kHeroW * z,
              height: kHeroH * z,
              child: HeroStill(
                heroId: heroId,
                tier: tier,
                outfit: {item.slot.name: item.id},
              ),
            ),
          ],
        ),
      );
    });
  }
}
