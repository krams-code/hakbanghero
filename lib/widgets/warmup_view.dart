import 'dart:async';

import 'package:flutter/material.dart';

import 'block_ui.dart';

const _yellow = Color(0xFFFFD21F);
const _yellowEdge = Color(0xFF8A6D00);

/// Pre-Run Preparation (warm-up) in the Roblox block style.
/// Same public API as before: [onComplete] when the routine finishes,
/// [onSkip] when the player skips it.
class WarmUpView extends StatefulWidget {
  final VoidCallback onComplete;
  final VoidCallback onSkip;

  const WarmUpView({
    super.key,
    required this.onComplete,
    required this.onSkip,
  });

  @override
  State<WarmUpView> createState() => _WarmUpViewState();
}

class _WarmUpViewState extends State<WarmUpView> {
  Timer? _timer;
  bool _started = false;
  int _currentStep = 0;
  int _secondsLeft = 8;

  static const List<_Step> _steps = [
    _Step('🚶', 'EASY MARCH',
        'March or walk gently in place. Keep your movements relaxed.', 8),
    _Step('🔄', 'ANKLE CIRCLES',
        'Slowly rotate your ankles. Switch direction halfway through.', 8),
    _Step('🦵', 'LEG SWINGS',
        'Gently swing each leg forward and backward. Do not force the movement.',
        8),
    _Step('🏃', 'EASY WALK / JOG',
        'Start moving comfortably and gradually prepare for your run.', 8),
  ];

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startRoutine() {
    setState(() {
      _started = true;
      _currentStep = 0;
      _secondsLeft = _steps[0].seconds;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft > 1) {
        setState(() => _secondsLeft--);
        return;
      }
      if (_currentStep < _steps.length - 1) {
        setState(() {
          _currentStep++;
          _secondsLeft = _steps[_currentStep].seconds;
        });
      } else {
        _timer?.cancel();
        setState(() => _started = false);
        widget.onComplete();
      }
    });
  }

  void _skip() {
    _timer?.cancel();
    widget.onSkip();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Rb.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          child: Column(
            children: [
              Block(
                color: Rb.hud,
                edge: Rb.hudEdge,
                depth: 6,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Column(
                  children: [
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: BlockText('⚔️ PRE-RUN PREPARATION',
                          size: 20, stroke: 4.5),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _started
                          ? 'Prepare your body before starting your adventure.'
                          : 'A short warm-up is recommended before every run.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF2A2D31),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (_started) _active(_steps[_currentStep]) else _preview(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Idle: quest list + big buttons ────────────────────────────────────
  Widget _preview() {
    return Column(
      children: [
        Block(
          color: Rb.panel,
          edge: Rb.panelEdge,
          depth: 6,
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: BlockText('📜 TRAINING QUEST', size: 14, stroke: 3.5),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _steps.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i == _steps.length - 1 ? 0 : 10),
                  child: _stepRow(i + 1, _steps[i]),
                ),
              const SizedBox(height: 12),
              const BlockText('⏱ ABOUT 32 SECONDS',
                  size: 11, stroke: 3, color: Color(0xFFB8BDC4)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        PressBlock(
          color: _yellow,
          edge: _yellowEdge,
          depth: 10,
          radius: 18,
          padding: const EdgeInsets.symmetric(vertical: 20),
          onTap: _startRoutine,
          child: const SizedBox(
            width: double.infinity,
            child: Center(
              child: BlockText('🔥 START WARM-UP', size: 22, stroke: 5),
            ),
          ),
        ),
        const SizedBox(height: 18),
        PressBlock(
          color: const Color(0xFF6B7078),
          edge: const Color(0xFF1B1D20),
          depth: 3,
          radius: 12,
          padding: const EdgeInsets.symmetric(vertical: 13),
          onTap: _skip,
          child: const SizedBox(
            width: double.infinity,
            child: Center(
              child: BlockText('SKIP', size: 15, stroke: 3.5,
                  color: Color(0xFFD7DADD)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'You can skip the warm-up. There is no XP penalty for skipping.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFFB8BDC4),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _stepRow(int n, _Step s) {
    return Block(
      color: Rb.slot,
      edge: Rb.panelEdge,
      depth: 4,
      radius: 12,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          // bright yellow square number tile
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _yellow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black, width: 3),
            ),
            child: BlockText('$n',
                size: 20, stroke: 4, color: Colors.black),
          ),
          const SizedBox(width: 12),
          Text(s.icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: BlockText(s.title, size: 15, stroke: 3.5),
            ),
          ),
        ],
      ),
    );
  }

  // ── Running routine ───────────────────────────────────────────────────
  Widget _active(_Step step) {
    final progress =
        (_currentStep + 1 - _secondsLeft / step.seconds) / _steps.length;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Block(
                color: Rb.blue,
                edge: Rb.blueEdge,
                depth: 5,
                radius: 12,
                gloss: true,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: BlockText(
                      'STEP ${_currentStep + 1}/${_steps.length}',
                      size: 15,
                      stroke: 3.5),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Block(
              color: _yellow,
              edge: _yellowEdge,
              depth: 5,
              radius: 12,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: BlockText('${_secondsLeft}s',
                  size: 20, stroke: 4, color: Colors.black),
            ),
          ],
        ),
        const SizedBox(height: 14),
        BlockBar(value: progress, height: 22, color: Rb.neon),
        const SizedBox(height: 18),
        Block(
          color: Rb.panel,
          edge: Rb.panelEdge,
          depth: 7,
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
          child: Column(
            children: [
              Block(
                color: _yellow,
                edge: _yellowEdge,
                depth: 6,
                radius: 18,
                padding: EdgeInsets.zero,
                child: SizedBox(
                  width: 110,
                  height: 110,
                  child: Center(
                    child: Text(step.icon,
                        style: const TextStyle(fontSize: 56)),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: BlockText(step.title, size: 24, stroke: 5),
              ),
              const SizedBox(height: 10),
              Text(
                step.description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFD7DADD),
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        PressBlock(
          color: const Color(0xFF6B7078),
          edge: const Color(0xFF1B1D20),
          depth: 3,
          radius: 12,
          padding: const EdgeInsets.symmetric(vertical: 13),
          onTap: _skip,
          child: const SizedBox(
            width: double.infinity,
            child: Center(
              child: BlockText('SKIP WARM-UP', size: 14, stroke: 3.5,
                  color: Color(0xFFD7DADD)),
            ),
          ),
        ),
      ],
    );
  }
}

class _Step {
  final String icon;
  final String title;
  final String description;
  final int seconds;
  const _Step(this.icon, this.title, this.description, this.seconds);
}
