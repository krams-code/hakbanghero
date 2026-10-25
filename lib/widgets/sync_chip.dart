import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/run_saver.dart';
import 'block_ui.dart';

/// "1 RUN WAITING TO SYNC". Appears only while runs sit in the offline
/// outbox. Tap to try sending them now. Disappears by itself when empty.
class SyncChip extends StatefulWidget {
  const SyncChip({super.key});

  @override
  State<SyncChip> createState() => _SyncChipState();
}

class _SyncChipState extends State<SyncChip> {
  bool _busy = false;
  Timer? _retryT;

  @override
  void initState() {
    super.initState();
    RunOutbox.refresh();
    // quiet automatic retry while something is waiting
    _retryT = Timer.periodic(const Duration(seconds: 45), (_) {
      if (RunOutbox.pending.value > 0 && !_busy) _sync(silent: true);
    });
  }

  @override
  void dispose() {
    _retryT?.cancel();
    super.dispose();
  }

  Future<void> _sync({bool silent = false}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _busy) return;
    if (!silent) setState(() => _busy = true);
    try {
      final sent = await RunOutbox.flush(uid);
      if (!silent && mounted) {
        final err = RunOutbox.lastError.value;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            duration: const Duration(seconds: 6),
            content: Text(sent > 0
                ? '\u2705 $sent run${sent == 1 ? '' : 's'} saved!'
                : 'Still not saved. ${err ?? ''}'),
          ));
      }
    } finally {
      if (mounted && !silent) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: RunOutbox.pending,
      builder: (_, n, __) {
        if (n <= 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PressBlock(
            color: const Color(0xFF6B7078),
            edge: const Color(0xFF1B1D20),
            depth: 4,
            radius: 12,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            onTap: _busy ? null : _sync,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: BlockText(
                          _busy
                              ? '\u{1F4E1} SYNCING...'
                              : '\u{1F4E1} $n RUN${n == 1 ? '' : 'S'} WAITING TO SYNC • TAP TO RETRY',
                          size: 11,
                          stroke: 3,
                          align: TextAlign.center,
                        ),
                      ),
                      ValueListenableBuilder<String?>(
                        valueListenable: RunOutbox.lastError,
                        builder: (_, err, __) => err == null
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  err,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Color(0xFFFFD7CF),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
