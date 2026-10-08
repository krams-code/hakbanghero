import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/weekly.dart';

/// Outcome of looking a friend code up (step 1 of adding a friend).
enum LookupStatus { found, notFound, self, already, pending, error }

class FriendLookup {
  final LookupStatus status;
  final String? uid;
  final Map<String, dynamic>? data; // their public profile, for the confirm card
  const FriendLookup(this.status, {this.uid, this.data});
}

/// Outcome of actually sending the request (step 2, after the player confirms).
enum AddResult { sent, accepted, error }

/// Firestore layout (see firestore_round2.rules):
///   users/{uid}.friend_code                  "HERO-4F7K"
///   friend_codes/{code}                      { uid }          (lookup index)
///   friend_requests/{from}_{to}              { from, to, from_name, status }
///   users/{uid}/friends/{friendUid}          { name, since }  (written for BOTH)
///   challenges/{id}   LIVE duel: status pending -> lobby -> countdown -> active -> done
///                     (or declined / cancelled / forfeit / expired)
///                     { participants, from, to, distance_km, reward, status,
///                       ready{uid:bool}, progress{uid:km}, seen{uid:ts}, winner }
///   reports/{id}                             { reporter, reported, reason, note, recent[] }
///   chats/{minUid}_{maxUid}                  { members, last_text, last_from, last_at, read{uid} }
///   chats/{id}/messages/{mid}                { from, text, ts }
class FriendsService {
  FriendsService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> user(String uid) =>
      _db.collection('users').doc(uid);
  static CollectionReference<Map<String, dynamic>> friends(String uid) =>
      user(uid).collection('friends');
  static CollectionReference<Map<String, dynamic>> get requests =>
      _db.collection('friend_requests');
  static CollectionReference<Map<String, dynamic>> get challenges =>
      _db.collection('challenges');
  static CollectionReference<Map<String, dynamic>> get chats =>
      _db.collection('chats');

  // ───────────────────────── friend code ─────────────────────────

  // no 0/O/1/I so codes are easy to read out loud
  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// The player's own code; created (and reserved uniquely) on first use.
  static Future<String> ensureCode(String uid) async {
    final snap = await user(uid).get();
    final existing = snap.data()?['friend_code'] as String?;
    if (existing != null && existing.isNotEmpty) return existing;

    final rng = Random.secure();
    for (var i = 0; i < 8; i++) {
      final code =
          'HERO-${List.generate(4, (_) => _alphabet[rng.nextInt(_alphabet.length)]).join()}';
      final ref = _db.collection('friend_codes').doc(code);
      try {
        await _db.runTransaction((txn) async {
          if ((await txn.get(ref)).exists) throw 'taken';
          txn.set(ref, {'uid': uid});
          txn.set(user(uid), {'friend_code': code}, SetOptions(merge: true));
        });
        return code;
      } catch (_) {/* collision or network: try another code */}
    }
    return '';
  }

  // ───────────────────────── add a friend (2 steps) ─────────────────────────

  /// Step 1: validate the code and fetch the profile to show on a confirm card.
  static Future<FriendLookup> lookup(String me, String rawCode) async {
    var code = rawCode.trim().toUpperCase().replaceAll(' ', '');
    if (code.isEmpty) return const FriendLookup(LookupStatus.notFound);
    if (!code.startsWith('HERO-')) code = 'HERO-$code';
    try {
      final c = await _db.collection('friend_codes').doc(code).get();
      final other = c.data()?['uid'] as String?;
      if (!c.exists || other == null) return const FriendLookup(LookupStatus.notFound);
      if (other == me) return const FriendLookup(LookupStatus.self);

      final profile = (await user(other).get()).data();
      if (profile == null) return const FriendLookup(LookupStatus.notFound);
      // they blocked me: look exactly like "no such user"
      final theirBlocks = (profile['blocked_uids'] as List?)?.whereType<String>() ?? const [];
      if (theirBlocks.contains(me)) return const FriendLookup(LookupStatus.notFound);

      if ((await friends(me).doc(other).get()).exists) {
        return FriendLookup(LookupStatus.already, uid: other, data: profile);
      }
      final mine = await requests.doc('${me}_$other').get();
      if (mine.exists && mine.data()?['status'] == 'pending') {
        return FriendLookup(LookupStatus.pending, uid: other, data: profile);
      }
      return FriendLookup(LookupStatus.found, uid: other, data: profile);
    } catch (_) {
      return const FriendLookup(LookupStatus.error);
    }
  }

  /// Step 2: the player confirmed. If they already asked me, this just accepts.
  static Future<AddResult> requestTo({
    required String me,
    required String myName,
    required String otherUid,
  }) async {
    try {
      // adding someone you blocked un-blocks them
      await user(me).update({'blocked_uids': FieldValue.arrayRemove([otherUid])}).catchError((_) {});

      final reverse = await requests.doc('${otherUid}_$me').get();
      if (reverse.exists && reverse.data()?['status'] == 'pending') {
        await accept(me: me, myName: myName, fromUid: otherUid);
        return AddResult.accepted;
      }
      await requests.doc('${me}_$otherUid').set({
        'from': me,
        'to': otherUid,
        'from_name': myName,
        'status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
      });
      return AddResult.sent;
    } catch (_) {
      return AddResult.error;
    }
  }

  static Future<void> accept({
    required String me,
    required String myName,
    required String fromUid,
  }) async {
    final theirName =
        (await user(fromUid).get()).data()?['username'] as String? ?? 'Hero';
    final batch = _db.batch();
    batch.set(friends(me).doc(fromUid),
        {'name': theirName, 'since': FieldValue.serverTimestamp()});
    batch.set(friends(fromUid).doc(me),
        {'name': myName, 'since': FieldValue.serverTimestamp()});
    batch.update(requests.doc('${fromUid}_$me'), {'status': 'accepted'});
    await batch.commit();
  }

  static Future<void> decline(String fromUid, String me) =>
      requests.doc('${fromUid}_$me').delete();

  static Future<void> unfriend(String me, String other) async {
    final batch = _db.batch();
    batch.delete(friends(me).doc(other));
    batch.delete(friends(other).doc(me));
    await batch.commit();
  }

  /// Unfriend + hide from now on (they can no longer find me by code).
  static Future<void> block(String me, String other) async {
    await user(me).set(
        {'blocked_uids': FieldValue.arrayUnion([other])}, SetOptions(merge: true));
    await unfriend(me, other);
  }

  static Future<void> report({
    required String me,
    required String reported,
    required String reportedName,
    required String reason,
    String note = '',
    List<String> recent = const [],
  }) {
    return _db.collection('reports').add({
      'reporter': me,
      'reported': reported,
      'reported_name': reportedName,
      'reason': reason,
      'note': note.length > 300 ? note.substring(0, 300) : note,
      'recent': recent.take(8).toList(), // last messages, as evidence
      'created_at': FieldValue.serverTimestamp(),
      'status': 'open',
    });
  }

  // ───────────────────────── LIVE duels ─────────────────────────
  //
  // pending   invite sent
  // lobby     accepted; both players open the room and press READY
  // countdown both ready -> synchronized 3-2-1-GO
  // active    both are running in the room; progress syncs live
  // done      someone reached the distance (winner set)
  // forfeit   a player left mid-race (the other claims the win)
  // declined / cancelled / expired

  /// distance (km) -> Mana Crystals the winner earns.
  static const Map<int, int> rewardFor = {1: 20, 3: 40, 5: 60, 10: 100};
  static const int lobbyMinutes = 15;
  static const int countdownSeconds = 5;

  static Future<DocumentReference<Map<String, dynamic>>> sendChallenge({
    required String me,
    required String myName,
    required String otherUid,
    required String otherName,
    required int km,
  }) {
    return challenges.add({
      'participants': [me, otherUid],
      'from': me,
      'to': otherUid,
      'from_name': myName,
      'to_name': otherName,
      'distance_km': km,
      'reward': rewardFor[km] ?? km * 10,
      'status': 'pending',
      'ready': {me: false, otherUid: false},
      'progress': {me: 0.0, otherUid: 0.0},
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> declineChallenge(String id) =>
      challenges.doc(id).update({'status': 'declined'});

  static Future<void> acceptChallenge(String id) => challenges.doc(id).update({
        'status': 'lobby',
        'accepted_at': FieldValue.serverTimestamp(),
        'lobby_expires': Timestamp.fromDate(
            DateTime.now().add(const Duration(minutes: lobbyMinutes))),
      });

  static Future<void> setReady(String id, String me, bool ready) =>
      challenges.doc(id).update({'ready.$me': ready});

  /// Idempotent: whichever client notices "both ready" flips the room.
  static Future<void> startCountdownIfReady(String id) async {
    await _db.runTransaction((txn) async {
      final s = await txn.get(challenges.doc(id));
      final d = s.data();
      if (d == null || d['status'] != 'lobby') return;
      final ready = (d['ready'] as Map?) ?? {};
      final parts = (d['participants'] as List).whereType<String>();
      if (!parts.every((u) => ready[u] == true)) return;
      txn.update(s.reference,
          {'status': 'countdown', 'countdown_at': FieldValue.serverTimestamp()});
    });
  }

  /// After the local 3-2-1-GO. Idempotent.
  static Future<void> goActive(String id) async {
    await _db.runTransaction((txn) async {
      final s = await txn.get(challenges.doc(id));
      if (s.data()?['status'] != 'countdown') return;
      txn.update(s.reference,
          {'status': 'active', 'started_at': FieldValue.serverTimestamp()});
    });
  }

  /// Live progress (also doubles as a "still here" heartbeat).
  static Future<void> pushProgress(String id, String me, double km) =>
      challenges.doc(id).update({
        'progress.$me': double.parse(km.toStringAsFixed(3)),
        'seen.$me': FieldValue.serverTimestamp(),
      });

  /// I reached the distance. True only for the FIRST finisher.
  static Future<bool> claimFinish(String id, String me, double km) async {
    var won = false;
    await _db.runTransaction((txn) async {
      final s = await txn.get(challenges.doc(id));
      final d = s.data();
      if (d == null || d['status'] != 'active') return;
      txn.update(s.reference, {
        'status': 'done',
        'winner': me,
        'finished_at': FieldValue.serverTimestamp(),
        'progress.$me': double.parse(km.toStringAsFixed(3)),
      });
      txn.update(user(me),
          {'gems': FieldValue.increment((d['reward'] as num).toInt())});
      won = true;
    });
    return won;
  }

  /// Leave the room. Mid-race this is a forfeit; before the race it just cancels.
  static Future<void> leave(String id, String me) async {
    await _db.runTransaction((txn) async {
      final s = await txn.get(challenges.doc(id));
      final st = s.data()?['status'];
      if (st == 'active') {
        txn.update(s.reference, {'status': 'forfeit', 'forfeit_by': me});
      } else if (st == 'lobby' || st == 'countdown') {
        txn.update(s.reference, {'status': 'cancelled', 'cancelled_by': me});
      }
    });
  }

  /// The opponent forfeited or went silent: take the win.
  static Future<bool> claimWin(String id, String me) async {
    var won = false;
    await _db.runTransaction((txn) async {
      final s = await txn.get(challenges.doc(id));
      final d = s.data();
      if (d == null) return;
      final st = d['status'];
      if (st != 'forfeit' && st != 'active') return;
      txn.update(s.reference, {
        'status': 'done',
        'winner': me,
        'finished_at': FieldValue.serverTimestamp(),
        'by_default': true,
      });
      txn.update(user(me),
          {'gems': FieldValue.increment((d['reward'] as num).toInt())});
      won = true;
    });
    return won;
  }

  // ───────────────────────── weekly km (for "friends this week") ─────────────────────────

  /// Fields to merge into the user doc when a run of [km] is saved.
  /// [userData] is the doc as read inside the same transaction.
  static Map<String, dynamic> weekFields(Map<String, dynamic> userData, double km) {
    final key = Weekly.key(DateTime.now());
    final same = userData['week_key'] == key;
    final prev = same ? ((userData['week_km'] as num?)?.toDouble() ?? 0) : 0.0;
    return {
      'week_key': key,
      'week_km': double.parse((prev + km).toStringAsFixed(3)),
      'last_run_at': FieldValue.serverTimestamp(),
    };
  }

  // ───────────────────────── chat ─────────────────────────

  static String chatId(String a, String b) =>
      a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

  static const int maxMessage = 300;

  static Future<void> sendMessage({
    required String me,
    required String other,
    required String text,
  }) async {
    var t = text.trim();
    if (t.isEmpty) return;
    if (t.length > maxMessage) t = t.substring(0, maxMessage);
    final ref = chats.doc(chatId(me, other));
    final batch = _db.batch();
    batch.set(ref.collection('messages').doc(),
        {'from': me, 'text': t, 'ts': FieldValue.serverTimestamp()});
    batch.set(
      ref,
      {
        'members': [me, other],
        'last_text': t.length > 60 ? '${t.substring(0, 60)}…' : t,
        'last_from': me,
        'last_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  static Future<void> markRead(String me, String other) async {
    try {
      await chats.doc(chatId(me, other)).set({
        'members': [me, other],
        'read': {me: FieldValue.serverTimestamp()},
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}
