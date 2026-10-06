import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Onboarding-tutorial progress, stored on users/{uid}.
///
///   tutorial_done                    Phase 1 (pre-run walkthrough) finished
///   has_completed_first_run_tutorial Phase 2 (post-run walkthrough) finished
///
/// Brand-new heroes get BOTH set to `false` when they are created. Accounts
/// that predate the tutorial have no such field, so they never see it.
class TutorialProgress {
  const TutorialProgress._();

  /// Firestore field behind `hasCompletedFirstRunTutorial`.
  static const String firstRunField = 'has_completed_first_run_tutorial';

  /// `hasCompletedFirstRunTutorial` for a user document map
  /// (null = the account has no tutorial flag at all).
  static bool? hasCompletedFirstRunTutorial(Map<String, dynamic>? userDoc) =>
      userDoc?[firstRunField] as bool?;

  /// Phase 2 must run: the flag exists and is still false.
  static bool isFirstRunTutorialPending(Map<String, dynamic>? userDoc) =>
      hasCompletedFirstRunTutorial(userDoc) == false;

  /// Reads the flag from Firestore (cache is fine). False on any error, so a
  /// network problem can never trap the player behind the tutorial.
  static Future<bool> loadFirstRunPending() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      return isFirstRunTutorialPending(snap.data());
    } catch (_) {
      return false;
    }
  }

  /// hasCompletedFirstRunTutorial = true (persistent).
  static Future<void> markFirstRunDone() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({firstRunField: true});
    } catch (_) {
      // not fatal: worst case the walkthrough shows once more next run
    }
  }
}
