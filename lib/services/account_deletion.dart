import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

import 'presence.dart';
import 'private_data.dart';
import 'run_checkpoint.dart';
import 'usernames.dart';

/// Permanently deletes the signed-in player's account (Google Play requires
/// this inside the app): runs, weight history, private data, friendships,
/// friend code, username, presence, the profile, and finally the login.
///
/// Chat messages already sent stay in the other player's chat history.
abstract final class AccountDeletion {
  /// How this player signs in ('password' and/or 'google.com').
  static Set<String> providers() =>
      FirebaseAuth.instance.currentUser?.providerData
          .map((p) => p.providerId)
          .toSet() ??
      <String>{};

  /// Firebase only deletes a login that signed in recently, so confirm the
  /// player first. Throws FirebaseAuthException (e.g. wrong-password).
  static Future<void> reauthenticate({String? password}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    if (providers().contains('password')) {
      final email = user.email;
      if (email == null || password == null || password.isEmpty) {
        throw FirebaseAuthException(
            code: 'missing-password', message: 'Enter your password.');
      }
      await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: email, password: password));
      return;
    }
    final google = GoogleAuthProvider();
    if (kIsWeb) {
      await user.reauthenticateWithPopup(google);
    } else {
      await user.reauthenticateWithProvider(google);
    }
  }

  static Future<void> _deleteAll(Query<Map<String, dynamic>> q) async {
    final db = FirebaseFirestore.instance;
    while (true) {
      final snap = await q.limit(300).get();
      if (snap.docs.isEmpty) return;
      final batch = db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (snap.docs.length < 300) return;
    }
  }

  /// Call right after [reauthenticate].
  static Future<void> deleteEverything() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    final uid = user.uid;
    final db = FirebaseFirestore.instance;
    final me = db.collection('users').doc(uid);
    final data = (await me.get()).data() ?? <String, dynamic>{};

    Future<void> step(String what, Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        debugPrint('delete account ($what): $e');
      }
    }

    await Presence.I.stop();
    await step('activities', () => _deleteAll(me.collection('activities')));
    await step('pending runs', () => _deleteAll(me.collection('pending_runs')));
    await step('weight', () => _deleteAll(me.collection('weight_checkins')));
    await step('private', () => PrivateData.ref(uid).delete());
    await step('friends', () async {
      final fr = await me.collection('friends').get();
      for (final f in fr.docs) {
        final b = db.batch();
        b.delete(f.reference);
        b.delete(db.collection('users').doc(f.id).collection('friends').doc(uid));
        await b.commit();
      }
    });
    await step('requests', () => _deleteAll(
        db.collection('friend_requests').where('to', isEqualTo: uid)));
    final code = data['friend_code'] as String?;
    if (code != null && code.isNotEmpty) {
      await step('friend code', () => db.collection('friend_codes').doc(code).delete());
    }
    final name = data['username'] as String?;
    if (name != null) {
      await step('username', () async {
        final ref = db.collection('usernames').doc(Usernames.key(name));
        final u = await ref.get();
        if (u.data()?['uid'] == uid) await ref.delete();
      });
    }
    await step('presence', () => Presence.doc(uid).delete());
    await me.delete(); // must work: this is the profile everyone sees
    await RunCheckpoint.clear();
    await user.delete(); // the login itself
  }
}
