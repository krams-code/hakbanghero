import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/auth/login_screen.dart';
import '../services/account_deletion.dart';
import 'block_ui.dart';

/// DELETE ACCOUNT (Settings). Asks the player to type DELETE and to confirm
/// their login, deletes everything, then goes back to the login screen.
Future<void> showDeleteAccountDialog(BuildContext context) async {
  final nav = Navigator.of(context, rootNavigator: true);
  final done = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _DeleteAccountDialog(),
  );
  if (done == true) {
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _confirm = TextEditingController();
  final _password = TextEditingController();
  late final bool _usesPassword =
      AccountDeletion.providers().contains('password');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _confirm.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_confirm.text.trim().toUpperCase() != 'DELETE') {
      setState(() => _error = 'Type DELETE to confirm.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AccountDeletion.reauthenticate(password: _password.text);
      await AccountDeletion.deleteEverything();
      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'wrong-password' || 'invalid-credential' => 'Wrong password.',
        'missing-password' => 'Enter your password.',
        'popup-closed-by-user' ||
        'web-context-canceled' ||
        'canceled' ||
        'user-cancelled' =>
          'Sign-in was cancelled.',
        'too-many-requests' => 'Too many tries. Wait a minute and try again.',
        'network-request-failed' => 'No internet connection.',
        _ => e.message ?? 'Could not confirm your login.',
      };
      if (mounted) setState(() => _error = msg);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not delete the account. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.black, width: 2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Block(
        color: Rb.slate,
        edge: Colors.black,
        depth: 8,
        radius: 22,
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 42)),
              const SizedBox(height: 6),
              const BlockText('DELETE ACCOUNT',
                  size: 22, stroke: 5, color: Rb.red),
              const SizedBox(height: 8),
              const BlockText(
                'This deletes your hero, runs, coins, items, friends and '
                'weight history FOREVER. It cannot be undone.',
                size: 12,
                stroke: 3,
                align: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                    color: Colors.black, fontWeight: FontWeight.w800),
                decoration: _deco('Type DELETE'),
              ),
              if (_usesPassword) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  style: const TextStyle(
                      color: Colors.black, fontWeight: FontWeight.w800),
                  decoration: _deco('Your password'),
                ),
              ] else ...[
                const SizedBox(height: 8),
                const BlockText('You will be asked to sign in with Google again.',
                    size: 10.5, stroke: 2.5, align: TextAlign.center),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFFFFB4A8),
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ],
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: PressBlock(
                    color: const Color(0xFF6B7078),
                    edge: const Color(0xFF1B1D20),
                    depth: 5,
                    radius: 12,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onTap: _busy ? null : () => Navigator.of(context).pop(false),
                    child: const Center(
                        child: BlockText('CANCEL', size: 14, stroke: 3.5)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PressBlock(
                    color: Rb.red,
                    edge: Rb.redEdge,
                    depth: 5,
                    radius: 12,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onTap: _busy ? null : _go,
                    child: Center(
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 3, color: Colors.white))
                          : const BlockText('DELETE', size: 14, stroke: 3.5),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
