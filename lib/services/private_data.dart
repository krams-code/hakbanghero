import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Data only the player can see: users/{uid}/private/body
///   { email, height_cm, weight_kg }
///
/// Everything in users/{uid} itself is visible to other players (leaderboard,
/// friend cards), so personal and health data must never be stored there.
abstract final class PrivateData {
  /// Fields that used to live on the public user doc.
  static const List<String> fields = ['email', 'height_cm', 'weight_kg'];

  static DocumentReference<Map<String, dynamic>> ref(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('private')
          .doc('body');

  static Future<Map<String, dynamic>> load(String uid) async {
    try {
      return (await ref(uid).get()).data() ?? <String, dynamic>{};
    } catch (e) {
      debugPrint('private data read: $e');
      return <String, dynamic>{};
    }
  }

  /// Older accounts kept email / height / weight on the public doc: move them
  /// to the private doc once and remove them from the public one.
  static Future<void> migrate(String uid) async {
    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final d = (await userRef.get()).data();
      if (d == null || !fields.any(d.containsKey)) return;
      final batch = FirebaseFirestore.instance.batch();
      batch.set(
        ref(uid),
        {
          for (final f in fields)
            if (d[f] != null) f: d[f],
        },
        SetOptions(merge: true),
      );
      batch.update(userRef, {for (final f in fields) f: FieldValue.delete()});
      await batch.commit();
    } catch (e) {
      debugPrint('private data migration: $e');
    }
  }
}
