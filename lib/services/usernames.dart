import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// One player per username: usernames/{key} = { uid }.
///
/// [key] is the name in lower case with single spaces, so "Mark",
/// "mark" and " MARK " are the same name.
abstract final class Usernames {
  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('usernames');

  static String key(String name) => name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('/', '_');

  /// True when someone else already uses [name]. Errors count as "free" so a
  /// bad connection never blocks sign-up (the claim below is the real check).
  static Future<bool> isTaken(String name, {String? myUid}) async {
    final k = key(name);
    if (k.isEmpty) return false;
    try {
      final d = await _col.doc(k).get();
      return d.exists && d.data()?['uid'] != myUid;
    } catch (_) {
      return false;
    }
  }

  /// Reserve [name] for [uid]. Returns false if it belongs to someone else.
  static Future<bool> claim(String uid, String name) async {
    final k = key(name);
    if (k.isEmpty) return false;
    final ref = _col.doc(k);
    try {
      return await FirebaseFirestore.instance.runTransaction<bool>((txn) async {
        final d = await txn.get(ref);
        if (d.exists) return d.data()?['uid'] == uid;
        txn.set(ref, {'uid': uid, 'name': name.trim()});
        return true;
      });
    } catch (e) {
      debugPrint('username claim: $e');
      return false;
    }
  }

  /// [base] if free, else [base] + a number ("Mark" -> "Mark4821").
  static Future<String> claimFree(String uid, String base) async {
    final clean = base.trim().isEmpty ? 'Hero' : base.trim();
    if (await claim(uid, clean)) return clean;
    final rng = Random();
    for (var i = 0; i < 6; i++) {
      final cand = '$clean${1000 + rng.nextInt(9000)}';
      if (await claim(uid, cand)) return cand;
    }
    return clean;
  }

  /// Accounts made before names were unique: reserve their current name if
  /// nobody else has it yet (marks the user doc with `username_key`).
  static Future<void> claimExisting(String uid) async {
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      final d = (await ref.get()).data();
      final name = d?['username'] as String?;
      if (d == null || name == null || d['username_key'] != null) return;
      if (await claim(uid, name)) {
        await ref.update({'username_key': key(name)});
      }
    } catch (e) {
      debugPrint('username migrate: $e');
    }
  }
}
