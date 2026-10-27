import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hakbanghero/services/usernames.dart';
import 'package:hakbanghero/services/private_data.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/outfit_catalog.dart';

/// Result of a Google sign-in attempt.
class GoogleAuthResult {
  const GoogleAuthResult({this.user, this.message, this.cancelled = false});
  final User? user;
  final String? message;
  final bool cancelled;
  bool get ok => user != null;
}

/// Google sign-in that works on web AND Android/iOS.
/// Web uses a popup; mobile uses Firebase's native provider flow
/// (a Chrome Custom Tab) so no extra plugin is required.
class GoogleAuth {
  GoogleAuth._();

  static Future<GoogleAuthResult> signIn() async {
    final provider = GoogleAuthProvider()..addScope('email');
    try {
      final auth = FirebaseAuth.instance;
      final cred = kIsWeb
          ? await auth.signInWithPopup(provider)
          : await auth.signInWithProvider(provider);
      final user = cred.user;
      if (user == null) {
        return const GoogleAuthResult(message: 'Google sign-in failed. Try again.');
      }
      await ensureUserDoc(user, user.displayName ?? 'Hero');
      return GoogleAuthResult(user: user);
    } on FirebaseAuthException catch (e) {
      const cancelCodes = {
        'canceled',
        'cancelled',
        'popup-closed-by-user',
        'cancelled-popup-request',
        'web-context-canceled',
        'web-context-cancelled',
      };
      if (cancelCodes.contains(e.code)) {
        return const GoogleAuthResult(
            cancelled: true, message: 'Google sign-in cancelled.');
      }
      if (e.code == 'account-exists-with-different-credential') {
        return const GoogleAuthResult(
            message:
                'This email is already registered with a password. Log in with your email instead.');
      }
      if (e.code == 'network-request-failed') {
        return const GoogleAuthResult(
            message: 'No internet connection. Check your network and try again.');
      }
      return GoogleAuthResult(
          message: e.message ?? 'Google sign-in failed. Try again.');
    } catch (_) {
      return const GoogleAuthResult(message: 'Google sign-in failed. Try again.');
    }
  }

  /// Creates the users/{uid} document for a first-time account (idempotent).
  static Future<void> ensureUserDoc(User user, String username,
      {String? gender}) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final doc = await ref.get();
    if (doc.exists) return;
    // one player per name: "Mark" may become "Mark4821"
    final name = await Usernames.claimFree(user.uid, username);
    await ref.set({
      'username': name,
      'username_key': Usernames.key(name),
      'gender': gender,
      'level': 1,
      'xp': 0,
      'coins': 100,
      'heroic_souls': 0,
      'total_km': 0.0,
      'total_steps': 0,
      'total_sessions': 0,
      'created_at': FieldValue.serverTimestamp(),
      'character_created': false,
      'skin_tone': '#E0AC69',
      ...StarterPack.toFirestore(),
      'owned_items': StarterPack.ownedItems,
      'hair_color': '#1A1A1A',
      'body_tier': 'average',
    });
    // private: only this player can read it
    await PrivateData.ref(user.uid)
        .set({'email': user.email}, SetOptions(merge: true))
        .catchError((Object _) {});
  }
}
