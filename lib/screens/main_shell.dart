import '../services/sound.dart';
import '../services/presence.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'activity/activity_screen.dart';
import 'leaderboard/leaderboard_screen.dart';
import 'profile/profile_screen.dart';

import 'package:hakbanghero/screens/character/equipment_screen.dart';
import 'package:hakbanghero/screens/shop/avatar_shop_screen.dart';
import 'package:hakbanghero/run/run_tracking_screen.dart';

import '../models/hero_roster.dart';
import '../state/evolution_state.dart';
import 'character/hero_picker_screen.dart';
import '../widgets/block_navbar.dart';
import '../widgets/block_ui.dart';
import '../widgets/evolution_checkin_dialog.dart';
import '../widgets/block_inputs.dart' show blockSnack;
import '../widgets/global_top_bar.dart';
import '../widgets/onboarding_tutorial.dart';
import '../widgets/tutorial_keys.dart';
import '../utils/perf_probe.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  FriendWatcher? _friendWatcher;

  @override
  void dispose() {
    _friendWatcher?.dispose();
    super.dispose();
  }
  // 0 = SHOP, 1 = GEAR, 2 = RUN, 3 = RANKS, 4 = ACTIVITY, 5 = PROFILE
  int _currentIndex = 2;

  /// True from warm-up until the session summary is dismissed.
  /// While true the bottom nav bar is removed so a stray tap can't
  /// interrupt tracking.
  bool _isTrackingActive = false;

  bool _bodiesPrecached = false;

  // ── Speed ───────────────────────────────────────────────────────────
  // Tabs are built the first time you open them (not all six at launch),
  // then kept alive. Each screen object is created ONCE, so switching tabs
  // doesn't rebuild every screen and reconnect their Firestore listeners.
  static const _tabNames = ['SHOP', 'GEAR', 'RUN', 'RANKS', 'ACTIVITY', 'PROFILE'];
  final Set<int> _visited = {2};
  final List<Widget?> _cache = List<Widget?>.filled(6, null);
  late final Widget _topBar = GlobalTopBar(onOpenProfile: () => _navigateTo(5));

  @override
  void initState() {
    super.initState();
    // App-wide body-form state (follows sign-in/out by itself).
    EvolutionState.instance.start();
    final me = FirebaseAuth.instance.currentUser;
    if (me != null) {
      Presence.I.start(me.uid); // green / orange / red dot for friends
      _friendWatcher = FriendWatcher(me.uid, (name) {
        if (mounted) {
          blockSnack(context, '\u{1F7E2} $name is online \u2014 challenge them to a duel!');
        }
      })
        ..start();
    }
    Sound.I.music(Bgm.menu);
    PerfProbe.start(); // frame / jank meter (debug + profile builds only)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _maybeAskGender();
      await _maybeChooseHero();
      await _maybeStartTutorial();
      await _migrateCrystals();
      await _maybeWeeklyCheckIn();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_bodiesPrecached) {
      _bodiesPrecached = true;
      // Decode all four body sprites now, so an evolution swap is a
      // synchronous ImageCache hit (zero asset-loading lag).
      EvolutionState.instance.precacheBodies(context);
    }
  }

  void _navigateTo(int index) {
    if (_isTrackingActive) return; // belt and braces
    if (index == _currentIndex) return;
    Sound.I.play(Sfx.tab);
    PerfProbe.markNav(_tabNames[index]);
    setState(() {
      _visited.add(index);
      _currentIndex = index;
    });
  }

  void _onTrackingChanged(bool active) {
    if (_isTrackingActive == active) return;
    if (!active) Sound.I.music(Bgm.menu); // run is over: back to menu music
    setState(() {
      _isTrackingActive = active;
      if (active) _currentIndex = 2;
    });
  }

  // ── Weekly check-in ────────────────────────────────────────────────────
  // Once a week the check-in pops up by itself right after the app starts, so
  // the hero's body keeps following the player's real progress. It cannot be
  // done at any other time (the profile button stays locked until it is due).
  /// Crystals were removed: coins are the only currency now. Anything left on
  /// an old account is cashed in once (1 crystal = 10 coins).
  Future<void> _migrateCrystals() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      final d = (await ref.get()).data();
      final g = (d?['gems'] as num?)?.toInt() ?? 0;
      if (g > 0) {
        await ref.update({'coins': FieldValue.increment(g * 10), 'gems': 0});
      }
    } catch (_) {}
  }

  Future<void> _maybeWeeklyCheckIn() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final d = snap.data();
      if (d == null) return;
      if (d['tutorial_done'] == false) return; // never during onboarding
      if (!EvolutionState.isCheckInDue(d)) return;
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      final r = await showEvolutionCheckIn(context);
      if (!mounted || r == null) return;
      blockSnack(
        context,
        r.improved
            ? '\u{1F525} EVOLVED INTO ${r.after.label.toUpperCase()}!'
                '${r.enduranceAwarded ? '  +${EvolutionState.enduranceBonus} ENDURANCE' : ''}'
            : '\u{1F4BE} Check-in saved: ${r.after.label}',
      );
    } catch (_) {
      // never block the app on the check-in
    }
  }

  // First launch with heroes: accounts that never picked one choose now.
  /// Older / Google accounts have no gender saved, so they are missing from
  /// the BOYS / GIRLS boards and always look like boy SPROUT. Ask once.
  Future<void> _maybeAskGender() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      final data = (await ref.get()).data();
      if (data == null || data['character_created'] == false) return;
      if (genderKey(data['gender']) != null || !mounted) return;
      final pick = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          Widget choice(String value, String label, Color c, Color e) => Expanded(
                child: PressBlock(
                  color: c,
                  edge: e,
                  depth: 5,
                  radius: 14,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  onTap: () => Navigator.of(ctx).pop(value),
                  child: Center(child: BlockText(label, size: 17, stroke: 4)),
                ),
              );
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(22),
            child: Block(
              color: Rb.slate,
              edge: Rb.slateEdge,
              depth: 6,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BlockText('BOY OR GIRL?',
                      size: 20, stroke: 4.5, align: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text(
                    'Pick one so your hero looks right and you show up on the '
                    'BOYS or GIRLS leaderboard.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Color(0xFFD7DADD),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    choice('male', '\u2642 BOY', Rb.blue, Rb.blueEdge),
                    const SizedBox(width: 10),
                    choice('female', '\u2640 GIRL', const Color(0xFFFF5FA2),
                        const Color(0xFF8A1F55)),
                  ]),
                ],
              ),
            ),
          );
        },
      );
      if (pick != null) await ref.update({'gender': pick});
    } catch (_) {
      // never block the app on this; it asks again next launch
    }
  }

  Future<void> _maybeChooseHero() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snap.data();
      if (data == null || hasChosenHero(data)) return;
      if (data['character_created'] == false) return; // creation screen picks
      if (!mounted) return;
      await Navigator.of(context).push<bool>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const HeroPickerScreen(firstTime: true),
      ));
    } catch (_) {
      // never block the app on the picker
    }
  }

  // ── Onboarding ────────────────────────────────────────────────────────
  // CharacterCreationScreen writes `tutorial_done: false` for brand-new
  // players. Existing accounts have no such field, so they never see it.
  Future<void> _maybeStartTutorial() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await ref.get();
      if (snap.data()?['tutorial_done'] != false) return;
      if (!mounted) return;

      setState(() => _currentIndex = 2); // hero, milestone bar, RUN button
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;

      OnboardingTutorial.show(
        context,
        onFinished: () {
          ref.update({'tutorial_done': true}).catchError((_) {});
          // brand-new hero: now they must pick their first mode (NOVICE)
          TutorialKeys.requestFirstMode();
        },
      );
    } catch (_) {
      // never block the app on the tutorial
    }
  }

  Widget _build(int i) {
    switch (i) {
      case 0:
        return const AvatarShopScreen();
      case 1:
        return const EquipmentScreen();
      case 2:
        return RunTrackingScreen(
          onExit: () => _navigateTo(0),
          onActiveChanged: _onTrackingChanged,
          onNavigate: _navigateTo, // post-run tutorial drives the tabs
        );
      case 3:
        return const LeaderboardScreen();
      case 4:
        return const ActivityScreen();
      default:
        return ProfileScreen(onBackTap: () => _navigateTo(2));
    }
  }

  /// A visited tab: same widget object every time, repainted on its own
  /// layer, and its animations are paused while it's hidden.
  Widget _tab(int i) {
    if (!_visited.contains(i)) return const SizedBox.shrink();
    return TickerMode(
      enabled: i == _currentIndex,
      child: RepaintBoundary(child: _cache[i] ??= _build(i)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The profile/coins header belongs to the HOME (RUN) tab only. Every other
    // module has its own header, and it is hidden mid-run so nothing can
    // interrupt tracking.
    final showTopBar = !_isTrackingActive && _currentIndex == 2;
    return Scaffold(
      backgroundColor: Rb.bg,
      body: Column(
        children: [
          if (showTopBar) _topBar,
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              // when the top bar is shown it already covers the status-bar inset
              removeTop: showTopBar,
              child: Stack(
                children: [
                  IndexedStack(
                    index: _currentIndex,
                    children: [for (var i = 0; i < 6; i++) _tab(i)],
                  ),

                ],
              ),
            ),
          ),
        ],
      ),
      // Removed entirely during an active run.
      // Slides open when the run ends (and closes when a run starts).
      bottomNavigationBar: AnimatedSize(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: _isTrackingActive
            ? const SizedBox(width: double.infinity)
            : BlockNavBar(
                currentIndex: _currentIndex == 5 ? -1 : _currentIndex,
                onTap: _navigateTo,
              ),
      ),
    );
  }
}
