import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/weekly_goal.dart';
import '../utils/weekly.dart';
import 'block_ui.dart';

/// "WEEKLY GOAL" card for the RUN tab. Loads its own data, so it refreshes
/// every time the pre-run screen is shown (e.g. after finishing a run).
class WeeklyGoalCard extends StatefulWidget {
  const WeeklyGoalCard({super.key});

  @override
  State<WeeklyGoalCard> createState() => _WeeklyGoalCardState();
}

class _WeeklyGoalCardState extends State<WeeklyGoalCard> {
  WeeklyGoal? _goal;
  String _claimed = '';
  bool _busy = false;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _load();
  }

  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  Future<void> _load({GoalMode? forceMode}) async {
    if (_uid == null) return;
    try {
      final user = (await _ref.get()).data() ?? {};
      final mode = forceMode ?? WeeklyGoal.modeFrom(user['goal_mode'] as String?);
      final goal = WeeklyGoal.compute(await WeeklyGoal.loadSessions(_uid!), mode);
      final key = Weekly.key(DateTime.now());

      // Research log: remember what target this player was given this week.
      final log = user['weekly_goal_log'];
      final seen = log is Map && log[key] != null;
      if (!seen || forceMode != null) {
        _ref.set({
          'weekly_goal_log': {
            key: {
              'target_km': goal.targetKm,
              'baseline_km': double.parse(goal.baselineKm.toStringAsFixed(2)),
              'mode': mode.name,
            }
          }
        }, SetOptions(merge: true)).catchError((_) {});
      }
      if (!mounted) return;
      setState(() {
        _goal = goal;
        _claimed = (user['weekly_goal_claimed'] as String?) ?? '';
      });
    } catch (_) {}
  }

  Future<void> _toggleMode() async {
    final g = _goal;
    if (g == null || _uid == null) return;
    final next = g.mode == GoalMode.adaptive ? GoalMode.fixed : GoalMode.adaptive;
    await _ref.set({'goal_mode': next.name}, SetOptions(merge: true));
    await _load(forceMode: next);
  }

  Future<void> _claim() async {
    final g = _goal;
    if (g == null || !g.reached || _busy || _uid == null) return;
    final key = Weekly.key(DateTime.now());
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final snap = await txn.get(_ref);
        if ((snap.data()?['weekly_goal_claimed'] as String?) == key) throw 'done';
        txn.update(_ref, {
          'weekly_goal_claimed': key,
          'gems': FieldValue.increment(WeeklyGoal.rewardGems),
          'weekly_goal_log.$key.achieved_km': double.parse(g.weekKm.toStringAsFixed(2)),
        });
      });
      if (mounted) {
        setState(() => _claimed = key);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              content: Text('🎯 Weekly goal smashed! +${WeeklyGoal.rewardGems} 💎')));
      }
    } catch (_) {
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = _goal;
    if (g == null) return const SizedBox.shrink();
    final done = _claimed == Weekly.key(DateTime.now());
    final adaptive = g.mode == GoalMode.adaptive;

    final why = !adaptive
        ? 'Fixed goal for everyone'
        : g.weeksUsed == 0
            ? 'Starter goal — it adapts to you after your first full week'
            : 'Your last ${g.weeksUsed} wk avg ${g.baselineKm.toStringAsFixed(1)} km +10%';

    return Block(
      color: const Color(0xFF1E5F8F),
      edge: const Color(0xFF0A2B45),
      depth: 6,
      radius: 18,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BlockText('\u{1F3AF} WEEKLY GOAL', size: 13, stroke: 3.5),
              const Spacer(),
              PressBlock(
                color: Rb.slot,
                edge: Rb.slateEdge,
                depth: 3,
                radius: 8,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                onTap: _toggleMode,
                child: BlockText(adaptive ? 'ADAPTIVE' : 'FIXED', size: 9, stroke: 2.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              BlockText(g.weekKm.toStringAsFixed(1), size: 26, stroke: 5, color: Rb.neon),
              const SizedBox(width: 4),
              BlockText('/ ${g.targetKm.toStringAsFixed(1)} km', size: 14, stroke: 3.5),
              const Spacer(),
              BlockText(Weekly.countdown(DateTime.now()), size: 9, stroke: 2.5),
            ],
          ),
          const SizedBox(height: 6),
          BlockBar(value: g.fraction, height: 14, color: Rb.green),
          const SizedBox(height: 6),
          BlockText(why, size: 9.5, stroke: 2.5, color: const Color(0xFFB8D4EA)),
          if (g.reached) ...[
            const SizedBox(height: 8),
            done
                ? const BlockText('✔ GOAL REACHED — reward claimed',
                    size: 11, stroke: 3, color: Rb.neon)
                : PressBlock(
                    color: Rb.green,
                    edge: Rb.greenEdge,
                    depth: 5,
                    radius: 14,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    onTap: _busy ? null : _claim,
                    child: SizedBox(
                      width: double.infinity,
                      child: Center(
                        child: BlockText('CLAIM \u{1F48E}${WeeklyGoal.rewardGems}',
                            size: 14, stroke: 3.5),
                      ),
                    ),
                  ),
          ],
        ],
      ),
    );
  }
}
