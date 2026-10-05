import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

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

  final List<_WarmUpStepData> _steps = const [
    _WarmUpStepData(
      icon: '🚶',
      title: 'EASY MARCH',
      description:
          'March or walk gently in place. Keep your movements relaxed.',
      seconds: 8,
    ),
    _WarmUpStepData(
      icon: '🔄',
      title: 'ANKLE CIRCLES',
      description:
          'Slowly rotate your ankles. Switch direction halfway through.',
      seconds: 8,
    ),
    _WarmUpStepData(
      icon: '🦵',
      title: 'LEG SWINGS',
      description:
          'Gently swing each leg forward and backward. Do not force the movement.',
      seconds: 8,
    ),
    _WarmUpStepData(
      icon: '🏃',
      title: 'EASY WALK / JOG',
      description:
          'Start moving comfortably and gradually prepare for your run.',
      seconds: 8,
    ),
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

    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted) return;

        if (_secondsLeft > 1) {
          setState(() {
            _secondsLeft--;
          });
          return;
        }

        if (_currentStep < _steps.length - 1) {
          setState(() {
            _currentStep++;
            _secondsLeft = _steps[_currentStep].seconds;
          });
        } else {
          _timer?.cancel();

          setState(() {
            _started = false;
          });

          widget.onComplete();
        }
      },
    );
  }

  void _skip() {
    _timer?.cancel();
    widget.onSkip();
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_currentStep];

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            children: [
              const SizedBox(height: 8),

              const Text(
                '⚔️ PRE-RUN PREPARATION',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                _started
                    ? 'Prepare your body before starting your adventure.'
                    : 'A short warm-up is recommended before every run.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSub,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 28),

              if (!_started) ...[
                _buildPreviewCard(),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _startRoutine,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: const Text(
                      '🔥 START WARM-UP',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _skip,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSub,
                      side: const BorderSide(
                        color: AppColors.borderDim,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: const Text(
                      'SKIP',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                const Text(
                  'You can skip the warm-up. There is no XP penalty for skipping.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSub,
                    fontSize: 10,
                  ),
                ),
              ] else ...[
                _buildActiveRoutine(step),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgPanel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.gold.withOpacity(0.35),
        ),
      ),
      child: Column(
        children: [
          const Text(
            'TRAINING QUEST',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),

          const SizedBox(height: 18),

          _PreviewStep(
            number: '1',
            icon: '🚶',
            title: 'Easy March',
          ),

          _PreviewStep(
            number: '2',
            icon: '🔄',
            title: 'Ankle Circles',
          ),

          _PreviewStep(
            number: '3',
            icon: '🦵',
            title: 'Leg Swings',
          ),

          _PreviewStep(
            number: '4',
            icon: '🏃',
            title: 'Easy Walk / Jog',
          ),

          const SizedBox(height: 10),

          const Text(
            'About 32 seconds',
            style: TextStyle(
              color: AppColors.textSub,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveRoutine(_WarmUpStepData step) {
    final progress =
        (_currentStep + 1) / _steps.length;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'STEP ${_currentStep + 1}/${_steps.length}',
              style: const TextStyle(
                color: AppColors.textSub,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            Text(
              '${_secondsLeft}s',
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            backgroundColor: AppColors.bgCard,
            valueColor: const AlwaysStoppedAnimation<Color>(
              AppColors.gold,
            ),
          ),
        ),

        const SizedBox(height: 36),

        Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.gold.withOpacity(0.08),
            border: Border.all(
              color: AppColors.gold.withOpacity(0.4),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withOpacity(0.15),
                blurRadius: 30,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Center(
            child: Text(
              step.icon,
              style: const TextStyle(fontSize: 65),
            ),
          ),
        ),

        const SizedBox(height: 28),

        Text(
          step.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.gold,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),

        const SizedBox(height: 10),

        Text(
          step.description,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textSub,
            fontSize: 13,
            height: 1.5,
          ),
        ),

        const SizedBox(height: 30),

        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: _skip,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSub,
              side: const BorderSide(
                color: AppColors.borderDim,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'SKIP WARM-UP',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewStep extends StatelessWidget {
  final String number;
  final String icon;
  final String title;

  const _PreviewStep({
    required this.number,
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.gold,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          Text(
            icon,
            style: const TextStyle(fontSize: 22),
          ),

          const SizedBox(width: 10),

          Text(
            title,
            style: const TextStyle(
              color: AppColors.textMain,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _WarmUpStepData {
  final String icon;
  final String title;
  final String description;
  final int seconds;

  const _WarmUpStepData({
    required this.icon,
    required this.title,
    required this.description,
    required this.seconds,
  });
}