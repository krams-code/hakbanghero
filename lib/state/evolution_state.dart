import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/body_composition.dart';
import '../models/character_profile.dart';

/// What happened when the player locked in a check-in.
class EvolutionResult {
  final BodyCompositionState before;
  final BodyCompositionState after;
  final double bmi;

  /// The form got closer to Normal (Obese -> Overweight, etc).
  final bool improved;

  /// +10 Endurance was actually granted (see anti-farming note in lockIn).
  final bool enduranceAwarded;

  const EvolutionResult({
    required this.before,
    required this.after,
    required this.bmi,
    required this.improved,
    required this.enduranceAwarded,
  });
}

/// App-wide source of truth for the signed-in hero's body form.
///
///   Firestore users/{uid}  --snapshots-->  [composition]  --> every avatar
///
///  * [composition] is a ValueNotifier. AvatarPreview / HeroSprite listen to
///    it (when given an `ownerUid`), so Home, Start Session, the top bar,
///    Profile and the player's own Leaderboard row all repaint in the SAME
///    frame as the lock-in tap. No Firestore round trip is awaited.
///  * The four body PNGs are decoded into Flutter's ImageCache up front
///    ([precacheBodies]), so the swap never waits on an asset load.
///  * The notifier is DERIVED from the user document, never a separate
///    override. If anything else edits height/weight (the Edit Hero screen,
///    for instance) the notifier follows, and a failed write reverts itself.
class EvolutionState {
  EvolutionState._();
  static final EvolutionState instance = EvolutionState._();

  /// Endurance reward for evolving into a better form.
  static const int enduranceBonus = 10;

  /// How often the check-in is considered due.
  static const Duration checkInEvery = Duration(days: 7);

  /// Current form of the signed-in hero.
  final ValueNotifier<BodyCompositionState> composition =
      ValueNotifier<BodyCompositionState>(BodyCompositionState.normal);

  String? _uid;
  Map<String, dynamic> _data = const <String, dynamic>{};
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;

  /// uid of the signed-in player (null when signed out / not started).
  String? get uid => _uid;

  /// Latest users/{uid} document (empty until the first snapshot).
  Map<String, dynamic> get userData => _data;

  /// True if [ownerUid] is the signed-in hero (so its avatar should follow
  /// [composition]). Other players' avatars (leaderboard) never do.
  bool isOwner(String? ownerUid) => ownerUid != null && ownerUid == _uid;

  // ───────────────────────── lifecycle ─────────────────────────

  /// Idempotent. Call once from MainShell. Follows sign-in / sign-out by
  /// itself, so no change is needed in the logout flow.
  void start() {
    if (_authSub != null) return;
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_bind);
  }

  Future<void> stop() async {
    await _authSub?.cancel();
    _authSub = null;
    _bind(null);
  }

  void _bind(User? user) {
    _docSub?.cancel();
    _docSub = null;
    _uid = user?.uid;
    if (user == null) {
      _data = const <String, dynamic>{};
      composition.value = BodyCompositionState.normal;
      return;
    }
    _docSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen(_onDoc, onError: (Object _) {});
  }

  void _onDoc(DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data() ?? const <String, dynamic>{};
    _data = d;
    composition.value = compositionFromData(d);
  }

  /// Same rule the avatar widgets always used: BMI from height + weight when
  /// both exist, otherwise the stored `body_tier` string, otherwise Normal.
  static BodyCompositionState compositionFromData(Map<String, dynamic> d) {
    final h = (d['height_cm'] as num?)?.toDouble();
    final w = (d['weight_kg'] as num?)?.toDouble();
    if (h != null && w != null && h > 0 && w > 0) {
      return calculateBodyComposition(w, h);
    }
    return BodyCompositionState.fromId(d['body_tier'] as String?);
  }

  // ───────────────────────── zero-lag sprites ─────────────────────────

  /// Decode every body sprite (male + female sheets) into the ImageCache. Image.asset (used by
  /// PixelLayer) builds the same AssetImage key, so later swaps are
  /// synchronous cache hits.
  Future<void> precacheBodies(BuildContext context) {
    final jobs = <Future<void>>[
      // Both sheets: male + female (~8 small PNGs). The gender may not be
      // known yet at startup, and this keeps every swap a cache hit.
      for (final s in BodyCompositionState.values)
        for (final g in const ['male', 'female'])
          precacheImage(AssetImage(bodyAssetFor(s.tier, g)), context)
              .catchError((Object _) {}),
    ];
    return Future.wait(jobs);
  }

  // ───────────────────────── check-in ─────────────────────────

  /// True when the last check-in is older than [every] (or never happened).
  static bool isCheckInDue(Map<String, dynamic>? d,
      {Duration every = checkInEvery}) {
    final ts = d?['last_checkin_at'];
    if (ts is! Timestamp) return true;
    return DateTime.now().difference(ts.toDate()) >= every;
  }

  /// Would moving from the current form to [after] pay the Endurance bonus?
  /// Anti-farming: only when it beats the best form ever reached, so
  /// Obese -> Normal -> Obese -> Normal can't be looped for endless Endurance.
  /// (Client-side; enforce in a Cloud Function / security rules before
  /// treating Endurance as anything of value.)
  bool wouldAwardEndurance(BodyCompositionState after) {
    final before = composition.value;
    final bestRank = (_data['best_composition_rank'] as num?)?.toInt() ??
        before.distanceFromNormal;
    return after.improvesOn(before) && after.distanceFromNormal < bestRank;
  }

  /// Save a check-in and swap the hero's form everywhere, instantly.
  ///
  /// [heightCm] / [weightKg] are METRIC (convert before calling).
  /// Throws if the write is rejected; the notifier is rolled back first.
  Future<EvolutionResult> lockIn({
    required double heightCm,
    required double weightKg,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');

    final before = composition.value;
    final bmi = calculateBmi(weightKg, heightCm);
    final after = BodyCompositionState.fromBmi(bmi);
    final improved = after.improvesOn(before);

    final bestRank = (_data['best_composition_rank'] as num?)?.toInt() ??
        before.distanceFromNormal;
    final award = wouldAwardEndurance(after);

    // 1) Optimistic: every listening avatar repaints on the next frame.
    composition.value = after;

    // 2) Persist. Firestore applies the write to its local cache at once,
    //    so streams (Home, Leaderboard, ...) agree immediately as well.
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    try {
      await ref.update({
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'body_tier': after.tier.id,
        'best_composition_rank': math.min(bestRank, after.distanceFromNormal),
        'last_checkin_at': FieldValue.serverTimestamp(),
        if (award) 'endurance_bonus': FieldValue.increment(enduranceBonus),
      }).timeout(
        // Offline: the write is queued and syncs later. Don't hang the
        // dialog on a server ack that may be minutes away.
        const Duration(seconds: 6),
        onTimeout: () {},
      );
    } catch (_) {
      composition.value = before; // rejected -> roll back
      rethrow;
    }

    unawaited(_logHistory(ref, heightCm, weightKg, bmi, after));

    return EvolutionResult(
      before: before,
      after: after,
      bmi: bmi,
      improved: improved,
      enduranceAwarded: award,
    );
  }

  /// Best-effort history row (users/{uid}/weight_checkins). Failure (for
  /// example Firestore rules without this subcollection) never affects the
  /// lock-in itself.
  Future<void> _logHistory(
    DocumentReference<Map<String, dynamic>> ref,
    double heightCm,
    double weightKg,
    double bmi,
    BodyCompositionState state,
  ) async {
    try {
      await ref.collection('weight_checkins').add({
        'at': FieldValue.serverTimestamp(),
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'bmi': double.parse(bmi.toStringAsFixed(2)),
        'composition': state.id,
      });
    } catch (e) {
      if (kDebugMode) debugPrint('weight_checkins log skipped: $e');
    }
  }
}
