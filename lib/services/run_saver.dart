import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/daily_quest_definitions.dart';
import '../models/run_mode.dart';
import '../utils/route_splits.dart';
import 'friends_service.dart';

/// Everything needed to save one finished run. Plain JSON, so it can sit in
/// the outbox on the phone while the player is offline.
class RunPayload {
  /// Unique per run (start time in ms). Saving the same id twice does nothing.
  final String id;
  final String uid;
  final String modeId;
  final String? outcome;
  final bool good;
  final double rewardMult;

  /// ActivitySession.toFirestore() with startTime / endTime as ms integers.
  final Map<String, dynamic> fields;
  final List<dynamic> challenges;
  final Map<String, dynamic>? ghost;
  final int xp;
  final int coins;
  final int bonusCoins; // challenge + ghost bonus coins
  final int lootChests;
  final int elapsedSeconds;

  /// Interval Run stats: {rounds, fast_km, best_fast_pace_s?}. Null otherwise.
  final Map<String, dynamic>? interval;

  const RunPayload({
    required this.id,
    required this.uid,
    required this.modeId,
    required this.outcome,
    required this.good,
    required this.rewardMult,
    required this.fields,
    required this.challenges,
    required this.ghost,
    required this.xp,
    required this.coins,
    required this.bonusCoins,
    required this.lootChests,
    required this.elapsedSeconds,
    this.interval,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'uid': uid,
        'modeId': modeId,
        'outcome': outcome,
        'good': good,
        'rewardMult': rewardMult,
        'fields': fields,
        'challenges': challenges,
        'ghost': ghost,
        'xp': xp,
        'coins': coins,
        'bonusCoins': bonusCoins,
        'lootChests': lootChests,
        'elapsedSeconds': elapsedSeconds,
        'interval': interval,
      };

  factory RunPayload.fromJson(Map<String, dynamic> j) => RunPayload(
        id: j['id'] as String,
        uid: j['uid'] as String,
        modeId: j['modeId'] as String,
        outcome: j['outcome'] as String?,
        good: j['good'] as bool? ?? false,
        rewardMult: (j['rewardMult'] as num?)?.toDouble() ?? 1.0,
        fields: Map<String, dynamic>.from(j['fields'] as Map),
        challenges: List<dynamic>.from(j['challenges'] as List? ?? const []),
        ghost: j['ghost'] == null
            ? null
            : Map<String, dynamic>.from(j['ghost'] as Map),
        xp: (j['xp'] as num?)?.toInt() ?? 0,
        coins: (j['coins'] as num?)?.toInt() ?? 0,
        // old queued runs stored crystals (1 crystal = 10 coins)
        bonusCoins: (j['bonusCoins'] as num?)?.toInt() ??
            (((j['gems'] as num?)?.toInt() ?? 0) * 10),
        lootChests: (j['lootChests'] as num?)?.toInt() ?? 0,
        elapsedSeconds: (j['elapsedSeconds'] as num?)?.toInt() ?? 0,
        interval: j['interval'] == null
            ? null
            : Map<String, dynamic>.from(j['interval'] as Map),
      );
}

/// What the summary card needs from a finished save.
class RunSaveResult {
  final List<DailyQuest> completedQuests;
  final int stars;
  final int bonusCoins;
  final bool firstClear;
  final RunMode? unlockedRank;

  /// True when this run had already been saved before (nothing was written).
  final bool duplicate;

  /// The run overlaps a run already counted (e.g. it reached the server late
  /// from another phone): the record is kept, without rewards.
  final bool late;

  /// Interval Run: this run beat the player's best FAST pace.
  final bool intervalNewBest;

  const RunSaveResult({
    this.completedQuests = const [],
    this.stars = 0,
    this.bonusCoins = 0,
    this.firstClear = false,
    this.unlockedRank,
    this.duplicate = false,
    this.late = false,
    this.intervalNewBest = false,
  });
}

/// Saves a run in ONE atomic, repeat-safe transaction: the activity, the
/// player totals, daily quests and the stage record all land together or not
/// at all. If it cannot finish (offline, slow network) the run goes into the
/// on-phone outbox and is re-sent later by [RunOutbox.flush].
List<Map<String, double>> _route(Object? raw) => [
      if (raw is List)
        for (final p in raw)
          if (p is Map)
            {
              for (final e in p.entries)
                if (e.value is num) e.key.toString(): (e.value as num).toDouble(),
            },
    ];

abstract final class RunSaver {
  // Mobile data / Safari can be slow to open the first connection.
  static const Duration timeout = Duration(seconds: 30);

  /// Short, readable reason a save failed (shown on the summary / sync bar).
  static String describe(Object e) {
    if (e is TimeoutException) return 'timeout: no answer from the server';
    if (e is FirebaseException) {
      final msg = (e.message ?? '').replaceAll('\n', ' ');
      return '${e.code}: ${msg.length > 140 ? '${msg.substring(0, 140)}...' : msg}';
    }
    final t = e.toString();
    return t.length > 160 ? '${t.substring(0, 160)}...' : t;
  }

  /// True when the server answered "no" (rules / bad data), not just offline.
  static bool isRejected(Object e) =>
      e is FirebaseException &&
      const {'permission-denied', 'invalid-argument', 'failed-precondition'}
          .contains(e.code);

  static String todayString() => dayString(DateTime.now());

  static String dayString(DateTime n) =>
      '${n.year}-${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';

  /// Day number used by the daily coin cap (Manila time, UTC+8). The security
  /// rules compute the same number from the server clock.
  static int coinDay() =>
      (DateTime.now().millisecondsSinceEpoch + 28800000) ~/ 86400000;

  /// Calendar week number (weeks start Monday, Manila time). The security
  /// rules compute the same number: one weekly-goal claim per week.
  static int weekIdx() => (coinDay() + 3) ~/ 7;

  /// Most coins runs + duels may add per day (the security rules enforce the
  /// same number).
  static const int dailyCoinCap = 12000;

  /// [coins], cut down to what is left of today's cap (never refused).
  static int capToday(Map<String, dynamic> data, int coins) {
    final day = coinDay();
    final same = (data['coins_today_day'] as num?)?.toInt() == day;
    final before = same ? ((data['coins_today'] as num?)?.toInt() ?? 0) : 0;
    return coins.clamp(0, math.max(0, dailyCoinCap - before)).toInt();
  }

  /// `coins_today` bookkeeping for the daily coin cap, to merge into the
  /// user update that adds [addCoins].
  static Map<String, dynamic> coinsTodayFields(
      Map<String, dynamic> data, int addCoins) {
    final day = coinDay();
    final same = (data['coins_today_day'] as num?)?.toInt() == day;
    final before = same ? ((data['coins_today'] as num?)?.toInt() ?? 0) : 0;
    return {'coins_today': before + addCoins, 'coins_today_day': day};
  }

  static Future<RunSaveResult> save(RunPayload p) async {
    final db = FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(p.uid);
    final actRef = userRef.collection('activities').doc(p.id);
    final mode = RunMode.byId(p.modeId);
    final km = (p.fields['distanceKm'] as num?)?.toDouble() ?? 0.0;
    final startMs = (p.fields['startTime'] as num).toInt();
    final endMs = (p.fields['endTime'] as num).toInt();
    final startHour = DateTime.fromMillisecondsSinceEpoch(startMs).hour;
    final today = todayString();
    // the day the run happened (a run synced the next morning still counts
    // for the day it was run, not for today's quests)
    final runDay = dayString(DateTime.fromMillisecondsSinceEpoch(startMs));

    var result = const RunSaveResult();

    await db.runTransaction((txn) async {
      // Transactions can retry: always start from a clean slate.
      result = const RunSaveResult();

      final existing = await txn.get(actRef);
      if (existing.exists) {
        result = const RunSaveResult(duplicate: true);
        return;
      }
      final snap = await txn.get(userRef);
      final data = snap.data() ?? <String, dynamic>{};

      // Runs can't overlap in time (the rules check this too). A run that
      // starts before the last counted run ended arrived late, e.g. from
      // another phone: keep the record so nothing disappears, no rewards.
      final lastEnd =
          (data['last_run_end'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      if (startMs < lastEnd - 120000) {
        txn.set(actRef, {
          ...p.fields,
          'startTime': Timestamp.fromMillisecondsSinceEpoch(startMs),
          'endTime': Timestamp.fromMillisecondsSinceEpoch(endMs),
          'xpEarned': 0,
          'coinsEarned': 0,
          'mode': p.modeId,
          'late': true,
        });
        result = const RunSaveResult(late: true);
        return;
      }

      final storedDate = data['daily_progress_date'] as String? ?? '';
      var dailyKm = (data['daily_progress_km'] as num?)?.toDouble() ?? 0.0;
      var claimed = Map<String, dynamic>.from(
          data['daily_quests_claimed'] as Map? ?? {});
      if (storedDate != today) {
        dailyKm = 0.0;
        claimed = {};
      }
      // only a run from TODAY moves today's quests
      final countsToday = runDay == today;
      if (countsToday) dailyKm += km;

      var coins = 0; // quest + stage bonus coins
      final done = <DailyQuest>[];
      for (final q in countsToday ? kDailyQuests : const <DailyQuest>[]) {
        if (claimed[q.id] == true) continue;
        if (q.beforeHour != null && startHour >= q.beforeHour!) continue;
        if (dailyKm >= q.thresholdKm) {
          claimed[q.id] = true;
          coins += q.coinReward;
          done.add(q);
        }
      }

      // Stage record: stars + first-clear bonus (cleared stages only).
      Map<String, dynamic>? records;
      var stars = 0, bonus = 0;
      var first = false;
      RunMode? opened;
      if (mode != null && mode.isStage && p.good) {
        final all =
            Map<String, dynamic>.from(data['stage_records'] as Map? ?? {});
        final old = Map<String, dynamic>.from(all[mode.id] as Map? ?? {});
        final oldStars = (old['stars'] as num?)?.toInt() ?? 0;
        final oldBest = (old['best_secs'] as num?)?.toInt() ?? 0;
        final oldClears = (old['clears'] as num?)?.toInt() ?? 0;
        stars = mode.starsFor(p.elapsedSeconds);
        first = oldStars == 0;
        final newStars = stars > oldStars ? stars - oldStars : 0;
        bonus = (first ? mode.firstClearCoins : 0) + newStars * RunMode.starCoins;
        all[mode.id] = {
          'stars': math.max(stars, oldStars),
          'best_secs': oldBest > 0
              ? math.min(oldBest, p.elapsedSeconds)
              : p.elapsedSeconds,
          'clears': oldClears + 1,
        };
        records = all;
        coins += bonus;
        if (first) {
          // a rank opens the next rank; a trial opens the next time goal
          final pool = mode.isTrial ? kTrialModes : kStageModes;
          for (final m in pool) {
            if (m.requiresId == mode.id) opened = m;
          }
        }
      }

      // Interval Run personal bests (lower pace seconds = faster).
      var newBest = false;
      final iv = p.interval;
      final ivPace = (iv?['best_fast_pace_s'] as num?)?.toInt();
      final ivRounds = (iv?['rounds'] as num?)?.toInt() ?? 0;
      final oldPace = (data['interval_best_fast_pace_s'] as num?)?.toInt();
      final oldRounds = (data['interval_best_rounds'] as num?)?.toInt() ?? 0;
      if (ivPace != null && ivPace > 0 && (oldPace == null || ivPace < oldPace)) {
        newBest = true;
      }

      final fields = Map<String, dynamic>.from(p.fields)
        ..['startTime'] = Timestamp.fromMillisecondsSinceEpoch(startMs)
        ..['endTime'] = Timestamp.fromMillisecondsSinceEpoch(endMs)
        // same shape at a fraction of the size (fast Activity list)
        ..['routePoints'] = simplifyRoute(_route(p.fields['routePoints']));

      txn.set(actRef, {
        ...fields,
        if (p.challenges.isNotEmpty) 'challenges': p.challenges,
        if (p.ghost != null) 'ghost': p.ghost,
        if (iv != null) 'interval': iv,
        'mode': p.modeId,
        'reward_mult': p.rewardMult,
        if (p.outcome != null) 'stage_result': p.outcome,
      });

      final extraCoins = p.bonusCoins + coins;
      final addCoins = capToday(data, p.coins + extraCoins);
      txn.update(userRef, {
        'total_km': FieldValue.increment(km),
        'total_sessions': FieldValue.increment(1),
        // Security rules read this to find the run record that justifies the
        // reward (rewards can never exceed what that record shows).
        'last_run_id': p.id,
        // where the next run may start (rules: runs never overlap)
        'last_run_end': Timestamp.fromMillisecondsSinceEpoch(endMs),
        'xp': FieldValue.increment(p.xp),
        'coins': FieldValue.increment(addCoins),
        ...coinsTodayFields(data, addCoins),
        if (p.lootChests > 0) 'loot_chests': FieldValue.increment(p.lootChests),
        'daily_progress_km': dailyKm,
        'daily_progress_date': today,
        'daily_quests_claimed': claimed,
        // feeds "friends this week" on the RUN tab
        ...FriendsService.weekFields(data, km),
        if (records != null) 'stage_records': records,
        if (iv != null) 'interval_runs': FieldValue.increment(1),
        if (iv != null && ivRounds > oldRounds) 'interval_best_rounds': ivRounds,
        if (newBest) 'interval_best_fast_pace_s': ivPace,
      });

      result = RunSaveResult(
        completedQuests: done,
        stars: stars,
        bonusCoins: bonus,
        firstClear: first,
        unlockedRank: opened,
        intervalNewBest: newBest,
      );
    });

    return result;
  }
}

/// CLOUD COPY of finished runs: users/{uid}/pending_runs/{runId}.
///
/// The moment a run ends it is uploaded here (a plain write, so Firebase
/// queues and retries it on weak signal, and it survives a reload). Any
/// device signed in to the account then counts it with [RunSaver.save] and
/// deletes the copy, so a run never depends on the phone it was recorded on.
abstract final class RunCloud {
  static CollectionReference<Map<String, dynamic>> _col(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('pending_runs');

  /// Upload (fire and forget; Firebase keeps retrying offline).
  static void stash(RunPayload p) {
    _col(p.uid)
        .doc(p.id)
        .set({...p.toJson(), 'created_at': FieldValue.serverTimestamp()})
        .catchError((Object e) => debugPrint('pending_runs upload: $e'));
  }

  /// The run was counted: remove its cloud copy.
  static Future<void> done(String uid, String id) async {
    try {
      await _col(uid).doc(id).delete();
    } catch (e) {
      debugPrint('pending_runs delete: $e');
    }
  }

  /// Ids of runs waiting in the cloud for [uid].
  static Set<String> waitingIds = <String>{};

  /// Count every waiting cloud run of [uid]. Returns how many went through.
  static Future<int> flush(String uid) async {
    var sent = 0;
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _col(uid).get().timeout(RunSaver.timeout);
    } catch (e) {
      debugPrint('pending_runs read: $e');
      return 0;
    }
    final docs = [...snap.docs]..sort((a, b) => a.id.compareTo(b.id));
    final left = <String>{};
    for (final d in docs) {
      try {
        final p = RunPayload.fromJson(Map<String, dynamic>.from(d.data()));
        if (p.uid != uid) continue;
        await RunSaver.save(p).timeout(RunSaver.timeout);
        await done(uid, d.id);
        sent++;
        RunOutbox.lastError.value = null;
      } catch (e) {
        debugPrint('pending_runs save: $e');
        RunOutbox.lastError.value = RunSaver.describe(e);
        left.add(d.id);
      }
    }
    waitingIds = left;
    return sent;
  }
}

/// Runs that could not be saved yet. Lives in SharedPreferences, so it
/// survives closing the app. Re-sent on the next app start / next run.
abstract final class RunOutbox {
  static const _key = 'run_outbox_v1';
  static bool _flushing = false;

  /// How many runs of the SIGNED-IN player are waiting (drives the SYNC chip).
  static final ValueNotifier<int> pending = ValueNotifier<int>(0);

  /// Runs on this phone that belong to OTHER accounts (sent only when that
  /// account signs in here).
  static final ValueNotifier<int> pendingOther = ValueNotifier<int>(0);

  static void _count(List<RunPayload> list) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    // same run can be both on the phone and in the cloud: count it once
    final mine = {
      for (final p in list)
        if (p.uid == me) p.id,
      ...RunCloud.waitingIds,
    };
    pending.value = mine.length;
    pendingOther.value = list.where((p) => p.uid != me).length;
  }

  /// Why the last send failed (null after a successful send).
  static final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  static Future<void> refresh() async {
    _count(await _load());
  }

  static Future<List<RunPayload>> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getStringList(_key) ?? const <String>[];
      final out = <RunPayload>[];
      for (final s in raw) {
        try {
          out.add(RunPayload.fromJson(jsonDecode(s) as Map<String, dynamic>));
        } catch (_) {
          // a damaged entry is dropped instead of blocking the queue
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _store(List<RunPayload> list) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(
          _key, [for (final p in list) jsonEncode(p.toJson())]);
      _count(list);
    } catch (e) {
      debugPrint('RunOutbox store failed: $e');
    }
  }

  static Future<void> enqueue(RunPayload p) async {
    final list = await _load();
    if (list.any((e) => e.id == p.id)) return;
    list.add(p);
    await _store(list);
  }

  static Future<int> pendingCount(String uid) async =>
      (await _load()).where((p) => p.uid == uid).length;

  /// Tries to send every waiting run of [uid]. Returns how many went through.
  static Future<int> flush(String uid) async {
    if (_flushing) return 0;
    _flushing = true;
    var sent = 0;
    try {
      final list = await _load();
      final left = <RunPayload>[];
      for (final p in list) {
        if (p.uid != uid) {
          left.add(p);
          continue;
        }
        try {
          await RunSaver.save(p).timeout(RunSaver.timeout);
          await RunCloud.done(p.uid, p.id);
          sent++;
          lastError.value = null;
        } catch (e) {
          debugPrint('RunOutbox send failed: $e');
          lastError.value = RunSaver.describe(e);
          left.add(p);
        }
      }
      if (sent > 0) await _store(left);
      // then runs waiting in the cloud (recorded on any device)
      sent += await RunCloud.flush(uid);
      _count(await _load());
    } finally {
      _flushing = false;
    }
    return sent;
  }
}
