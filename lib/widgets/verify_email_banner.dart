import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'block_ui.dart';

/// "Verify your email" reminder for email sign-ups (Google accounts are
/// already verified). Shows on Home until the link in the email is opened.
class VerifyEmailBanner extends StatefulWidget {
  const VerifyEmailBanner({super.key});

  @override
  State<VerifyEmailBanner> createState() => _VerifyEmailBannerState();
}

class _VerifyEmailBannerState extends State<VerifyEmailBanner> {
  bool _busy = false;
  String? _note;

  User? get _user => FirebaseAuth.instance.currentUser;

  bool get _show {
    final u = _user;
    if (u == null || u.emailVerified || u.email == null) return false;
    return u.providerData.any((p) => p.providerId == 'password');
  }

  Future<void> _resend() async {
    setState(() => _busy = true);
    try {
      await _user?.sendEmailVerification();
      _note = 'Sent! Check your inbox (and spam folder).';
    } on FirebaseAuthException catch (e) {
      _note = e.code == 'too-many-requests'
          ? 'Already sent. Wait a few minutes before asking again.'
          : 'Could not send. Try again later.';
    } catch (_) {
      _note = 'Could not send. Try again later.';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      await _user?.reload();
      if (_show) _note = 'Not verified yet. Open the link in the email first.';
    } catch (_) {
      _note = 'Could not check. Try again.';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    Widget btn(String label, VoidCallback onTap) => Expanded(
          child: PressBlock(
            color: Rb.blue,
            edge: Rb.blueEdge,
            depth: 4,
            radius: 10,
            padding: const EdgeInsets.symmetric(vertical: 8),
            onTap: _busy ? null : onTap,
            child: Center(child: BlockText(label, size: 11, stroke: 3)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Block(
        color: const Color(0xFF7A5A0A),
        edge: const Color(0xFF3A2A00),
        depth: 5,
        radius: 14,
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          BlockText(
            '\u{1F4E7} VERIFY YOUR EMAIL\nWe sent a link to ${_user!.email}.',
            size: 12,
            stroke: 3,
            align: TextAlign.center,
          ),
          if (_note != null) ...[
            const SizedBox(height: 6),
            Text(_note!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ],
          const SizedBox(height: 8),
          Row(children: [
            btn('SEND AGAIN', _resend),
            const SizedBox(width: 8),
            btn('I VERIFIED IT', _check),
          ]),
        ]),
      ),
    );
  }
}
