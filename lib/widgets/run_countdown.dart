import 'dart:async';

import 'package:flutter/material.dart';

import '../services/sound.dart';
import 'block_ui.dart';

/// "3 ... 2 ... 1 ... GO!" shown right before the run starts, so the player
/// can put the phone away and get ready (the run no longer starts instantly
/// when the warm-up ends or is skipped).
class RunCountdown extends StatefulWidget {
  final int seconds;
  final String modeName;
  final VoidCallback onDone;
  final VoidCallback onCancel;

  const RunCountdown({
    super.key,
    this.seconds = 3,
    required this.modeName,
    required this.onDone,
    required this.onCancel,
  });

  @override
  State<RunCountdown> createState() => _RunCountdownState();
}

class _RunCountdownState extends State<RunCountdown> {
  late int _n = widget.seconds;
  Timer? _t;
  Timer? _go;

  @override
  void initState() {
    super.initState();
    Sound.I.play(Sfx.beep);
    Sound.I.buzz(1);
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _n--);
      if (_n > 0) {
        Sound.I.play(Sfx.beep);
        Sound.I.buzz(1);
      } else {
        t.cancel();
        // hold "GO!" for a beat, then the run starts (and plays its own GO)
        _go = Timer(const Duration(milliseconds: 450), () {
          if (mounted) widget.onDone();
        });
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _go?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final go = _n <= 0;
    // Full width so the column is centred (the Scaffold body gives loose
    // constraints, which otherwise shrink it and pin it to the left).
    return SafeArea(
      child: SizedBox(
        width: double.infinity,
        child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Spacer(),
            const BlockText('GET READY!', size: 22, stroke: 5),
            const SizedBox(height: 4),
            BlockText(widget.modeName.toUpperCase(),
                size: 13, stroke: 3.5, color: const Color(0xFFD7DADD)),
            const SizedBox(height: 18),
            SizedBox(
              height: 190,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.elasticOut,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 1.7, end: 1.0).animate(anim),
                    child: child,
                  ),
                ),
                child: BlockText(
                  go ? 'GO!' : '$_n',
                  key: ValueKey<int>(_n),
                  size: go ? 110 : 150,
                  stroke: 9,
                  color: go ? Rb.neon : Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const BlockText('Phone in your pocket, then start moving!',
                size: 12, stroke: 3, align: TextAlign.center),
            const Spacer(),
            if (!go)
              PressBlock(
                color: Rb.red,
                edge: Rb.redEdge,
                depth: 6,
                radius: 14,
                sfx: Sfx.back,
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 11),
                onTap: widget.onCancel,
                child: const BlockText('CANCEL', size: 15, stroke: 4),
              ),
          ],
        ),
      ),
      ),
    );
  }
}
