import 'dart:async';

import 'package:flutter/material.dart';

import '../challenges/challenge_engine.dart';
import 'block_ui.dart';

const Color _yellow = Color(0xFFFFD21F);
const Color _neonRed = Color(0xFFFF2B4A);

String _mmss(int s) =>
    '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

String _pace(int? secPerKm) => secPerKm == null
    ? '--'
    : "${secPerKm ~/ 60}'${(secPerKm % 60).toString().padLeft(2, '0')}\"";

/// Everything the player sees for a sudden challenge, drawn over the live
/// tracker:
///   1. a big centred "SUDDEN QUEST" pop-up (~2.4 s, with the live clock)
///   2. a compact countdown HUD under the header while it runs
///   3. a big result banner (complete / failed) for ~3.4 s
///
/// It ignores touches, so PAUSE / FINISH stay usable underneath.
class ChallengeOverlay extends StatefulWidget {
  final ChallengeEngine engine;
  const ChallengeOverlay({super.key, required this.engine});

  @override
  State<ChallengeOverlay> createState() => _ChallengeOverlayState();
}

class _ChallengeOverlayState extends State<ChallengeOverlay>
    with SingleTickerProviderStateMixin {
  static const Duration _announceFor = Duration(milliseconds: 2400);
  static const Duration _resultFor = Duration(milliseconds: 3400);

  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  Timer? _announceTimer;
  Timer? _resultTimer;
  bool _announcing = false;
  int _seenSerial = 0;
  int _seenResult = 0;

  @override
  void initState() {
    super.initState();
    _seenSerial = widget.engine.serial;
    _seenResult = widget.engine.resultSerial;
    widget.engine.addListener(_onEngine);
  }

  @override
  void dispose() {
    widget.engine.removeListener(_onEngine);
    _announceTimer?.cancel();
    _resultTimer?.cancel();
    _pop.dispose();
    super.dispose();
  }

  void _onEngine() {
    if (!mounted) return;
    final e = widget.engine;

    if (e.serial != _seenSerial) {
      _seenSerial = e.serial;
      _resultTimer?.cancel();
      _announcing = true;
      _pop.forward(from: 0);
      _announceTimer?.cancel();
      _announceTimer = Timer(_announceFor, () {
        if (mounted) setState(() => _announcing = false);
      });
    }

    if (e.resultSerial != _seenResult) {
      _seenResult = e.resultSerial;
      if (e.lastResult != null) {
        _announceTimer?.cancel();
        _announcing = false;
        _pop.forward(from: 0);
        _resultTimer?.cancel();
        _resultTimer = Timer(_resultFor, () {
          if (mounted) widget.engine.dismissResult();
        });
      }
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.engine;
    final result = e.lastResult;

    Widget? center;
    if (result != null) {
      center = _ResultBanner(result: result, config: e.config);
    } else if (_announcing && e.isActive) {
      center = _AnnounceCard(engine: e);
    }

    return IgnorePointer(
      child: Stack(
        children: [
          if (center != null)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: result != null ? 0.4 : 0.55),
              ),
            ),
          if (center != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: AnimatedBuilder(
                  animation: _pop,
                  child: center,
                  builder: (_, child) => Transform.scale(
                    scale: Curves.elasticOut
                        .transform(_pop.value.clamp(0.0, 1.0))
                        .clamp(0.0, 1.4),
                    child: child,
                  ),
                ),
              ),
            ),
          if (e.isActive && !_announcing)
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 78, 22, 0),
                child: _Hud(engine: e),
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────── copy ─────────────────────────

String _title(ChallengeKind k) => k == ChallengeKind.sprintBlitz
    ? '⚠️ SUDDEN QUEST: SPRINT BLITZ!'
    : '⏱️ TIME TRIAL: PACE KEEPER!';

String _target(ChallengeEngine e) {
  final c = e.config;
  return e.activeKind == ChallengeKind.sprintBlitz
      ? 'Sprint ${c.sprintTargetMeters.round()} meters in the next '
          '${c.sprintSeconds} seconds!'
      : 'Finish your next ${c.paceSectionKm.toStringAsFixed(1)} km section '
          'in under ${c.paceSeconds ~/ 60} minutes!';
}

// ───────────────────────── pop-up ─────────────────────────

class _AnnounceCard extends StatelessWidget {
  final ChallengeEngine engine;
  const _AnnounceCard({required this.engine});

  @override
  Widget build(BuildContext context) {
    final kind = engine.activeKind ?? ChallengeKind.sprintBlitz;
    return Block(
      color: Rb.red,
      edge: Rb.redEdge,
      depth: 10,
      radius: 22,
      gloss: true,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: BlockText(_title(kind),
                size: 24, stroke: 6, color: _yellow),
          ),
          const SizedBox(height: 10),
          BlockText(_target(engine),
              size: 16, stroke: 4, align: TextAlign.center),
          const SizedBox(height: 12),
          Block(
            color: Colors.black,
            edge: Rb.redEdge,
            depth: 4,
            radius: 12,
            padding:
                const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
            child: BlockText(_mmss(engine.remainingSeconds),
                size: 40, stroke: 6, color: _yellow),
          ),
          if (kind == ChallengeKind.paceKeeper) ...[
            const SizedBox(height: 8),
            BlockText(
              '🚩 START ${engine.startMarkerKm.toStringAsFixed(2)} km  →  '
              '🏁 ${engine.finishMarkerKm.toStringAsFixed(2)} km',
              size: 12,
              stroke: 3,
            ),
          ],
          const SizedBox(height: 8),
          const BlockText('GO GO GO!', size: 18, stroke: 4.5),
        ],
      ),
    );
  }
}

// ───────────────────────── countdown HUD ─────────────────────────

class _Hud extends StatelessWidget {
  final ChallengeEngine engine;
  const _Hud({required this.engine});

  @override
  Widget build(BuildContext context) {
    final e = engine;
    final sprint = e.activeKind == ChallengeKind.sprintBlitz;
    final secs = e.remainingSeconds;
    final urgent = secs <= 5;

    final String progressText = sprint
        ? '${e.progressMeters.round()} / ${e.targetMeters.round()} m'
        : '${(e.progressMeters / 1000).toStringAsFixed(2)} / '
            '${e.config.paceSectionKm.toStringAsFixed(2)} km';

    Widget? paceLine;
    if (!sprint) {
      final split = e.splitPaceSecPerKm;
      final need = e.requiredPaceSecPerKm;
      final ok = e.onTrack;
      paceLine = Column(
        children: [
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: BlockText(
              'SPLIT ${_pace(split)}/km   •   NEED ${_pace(need)}/km  '
              '${split == null ? '' : (ok ? '✅' : '⚠️')}',
              size: 11,
              stroke: 3,
              color: split == null || ok ? Rb.neon : Rb.orange,
            ),
          ),
          const SizedBox(height: 2),
          BlockText(
            '🚩 ${e.startMarkerKm.toStringAsFixed(2)} km  →  '
            '🏁 ${e.finishMarkerKm.toStringAsFixed(2)} km',
            size: 10,
            stroke: 2.5,
            color: const Color(0xFFB8BDC4),
          ),
        ],
      );
    }

    return Block(
      color: const Color(0xFF2A0A0E),
      edge: _neonRed,
      depth: 5,
      radius: 14,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: BlockText(
                    sprint ? '⚡ SPRINT BLITZ' : '⏱️ PACE KEEPER',
                    size: 14,
                    stroke: 3.5,
                    color: _yellow,
                  ),
                ),
              ),
              BlockText(_mmss(secs),
                  size: 28,
                  stroke: 5,
                  color: urgent ? _neonRed : Colors.white),
            ],
          ),
          const SizedBox(height: 6),
          _Bar(
            fraction: e.progressFraction,
            color: sprint || e.onTrack ? Rb.neon : Rb.orange,
          ),
          const SizedBox(height: 4),
          BlockText(progressText, size: 12, stroke: 3),
          if (paceLine != null) paceLine,
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double fraction;
  final Color color;
  const _Bar({required this.fraction, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 16,
      decoration: BoxDecoration(
        color: Rb.track,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black, width: 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fraction.clamp(0.0, 1.0),
            child: Container(color: color),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── result banner ─────────────────────────

class _ResultBanner extends StatelessWidget {
  final ChallengeRecord result;
  final ChallengeConfig config;
  const _ResultBanner({required this.result, required this.config});

  @override
  Widget build(BuildContext context) {
    if (!result.success) {
      return Block(
        color: Rb.red,
        edge: Rb.redEdge,
        depth: 10,
        radius: 22,
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
        child: const BlockText(
          'Quest Failed! Keep pushing your limits!',
          size: 24,
          stroke: 6,
          align: TextAlign.center,
        ),
      );
    }

    final sprint = result.kind == ChallengeKind.sprintBlitz;
    return Block(
      color: Rb.gold,
      edge: Rb.goldEdge,
      depth: 10,
      radius: 22,
      gloss: true,
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: BlockText(
              sprint
                  ? '🏆 QUEST COMPLETE! +${result.bonusXp} EXP'
                  : '🏆 TIME TRIAL CLEARED!',
              size: 28,
              stroke: 7,
            ),
          ),
          const SizedBox(height: 10),
          if (sprint && result.bonusGems > 0)
            BlockText('💎 +${result.bonusGems} MANA CRYSTALS',
                size: 18, stroke: 4.5, color: Rb.neon),
          if (result.lootChest) ...[
            const BlockText('📦 LOOT CHEST DETECTED!',
                size: 20, stroke: 5, color: Colors.white),
            const SizedBox(height: 4),
            const BlockText('Waiting in your post-run summary!',
                size: 12, stroke: 3),
          ],
        ],
      ),
    );
  }
}
