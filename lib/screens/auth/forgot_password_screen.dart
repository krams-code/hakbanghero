import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _sendReset() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _snack('Please enter your email.');
      return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) setState(() => _sent = true);
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? 'Failed to send reset email.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060C06),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios,
                      color: Color(0xFF4A8A4A), size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(height: 24),
              const Icon(Icons.lock_reset,
                  color: Color(0xFF00FF41), size: 52),
              const SizedBox(height: 20),
              const Text(
                'RESET PASSWORD',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF00FF41),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Enter your email and we'll send you a reset link.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF4A7A4A), fontSize: 13),
              ),
              const SizedBox(height: 40),
              if (!_sent) ...[
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1A0D),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF1A3A1A)),
                  ),
                  child: TextField(
                    controller: _emailCtrl,
                    style: const TextStyle(
                        color: Color(0xFFD0EED0), fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Email',
                      hintStyle: TextStyle(
                          color: Color(0xFF3A6A3A), fontSize: 14),
                      prefixIcon: Icon(Icons.email_outlined,
                          color: Color(0xFF4A8A4A), size: 20),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                          vertical: 16, horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _sendReset,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FF41),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Color(0xFF0A0F0A),
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'SEND RESET LINK',
                            style: TextStyle(
                              color: Color(0xFF0A0F0A),
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D2A0D),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: const Color(0xFF00FF41).withOpacity(0.3)),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.check_circle,
                          color: Color(0xFF00FF41), size: 40),
                      SizedBox(height: 12),
                      Text(
                        'Reset email sent!',
                        style: TextStyle(
                          color: Color(0xFF00FF41),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Check your inbox and follow the link to reset your password.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Color(0xFF4A8A4A), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Back to Login',
                    style: TextStyle(
                        color: Color(0xFF00FF41),
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}