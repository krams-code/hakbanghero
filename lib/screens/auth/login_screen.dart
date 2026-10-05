import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../widgets/block_inputs.dart';
import '../../widgets/block_ui.dart';
import '../character/character_creation_screen.dart';
import '../main_shell.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  Future<void> _goHome() async {
    if (!mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    bool characterCreated = false;
    if (uid != null) {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      characterCreated = doc.data()?['character_created'] as bool? ?? false;
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) =>
            characterCreated ? const MainShell() : const CharacterCreationScreen(),
      ),
      (_) => false,
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    blockSnack(context, msg);
  }

  Future<void> _loginEmail() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text; // never trim a password
    if (email.isEmpty || pass.isEmpty) {
      _snack('Please fill in all fields.');
      return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: pass);
      _goHome();
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? 'Login failed.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginGoogle() async {
    setState(() => _loading = true);
    try {
      final cred =
          await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      if (mounted && cred.user != null) _goHome();
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? 'Google sign-in failed.');
    } catch (e) {
      _snack('Google sign-in failed. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Rb.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthBanner(
                    title: 'HAKBANG HERO',
                    subtitle: 'GAMIFIED FITNESS TRACKER',
                  ),
                  const SizedBox(height: 24),
                  Block(
                    color: Rb.panel,
                    edge: Rb.panelEdge,
                    depth: 6,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(
                          child: BlockText('🔐 PLAYER LOGIN', size: 18, stroke: 4.5),
                        ),
                        const SizedBox(height: 16),
                        BlockTextField(
                          label: 'EMAIL',
                          hint: 'hero@email.com',
                          icon: '✉️',
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          action: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),
                        BlockTextField(
                          label: 'PASSWORD',
                          hint: 'Your secret code',
                          icon: '🔒',
                          controller: _passCtrl,
                          obscure: _obscure,
                          action: TextInputAction.done,
                          onSubmitted: (_) => _loading ? null : _loginEmail(),
                          suffix: GestureDetector(
                            onTap: () => setState(() => _obscure = !_obscure),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(_obscure ? '🙈' : '👁️',
                                  style: const TextStyle(fontSize: 20)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: PressBlock(
                            color: Rb.slot,
                            edge: Rb.slateEdge,
                            depth: 3,
                            radius: 10,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ForgotPasswordScreen()),
                            ),
                            child: const BlockText('FORGOT PASSWORD?',
                                size: 10, stroke: 2.5),
                          ),
                        ),
                        const SizedBox(height: 18),
                        NeonBlueButton(
                          label: 'LOGIN',
                          loading: _loading,
                          onTap: _loginEmail,
                        ),
                        const SizedBox(height: 16),
                        PressBlock(
                          color: const Color(0xFFF2F3F5),
                          edge: const Color(0xFF6B6F75),
                          depth: 5,
                          radius: 14,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          onTap: _loading ? null : _loginGoogle,
                          child: const SizedBox(
                            width: double.infinity,
                            child: Center(
                              child: BlockText('G  CONTINUE WITH GOOGLE',
                                  size: 13, stroke: 3.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  // Onboarding focus: loud contrasting Sign Up block
                  Block(
                    color: const Color(0xFF3B2A00),
                    edge: Colors.black,
                    depth: 6,
                    radius: 18,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        const BlockText('NEW HERE? START YOUR ADVENTURE!',
                            size: 11, stroke: 3, color: Rb.gold),
                        const SizedBox(height: 10),
                        PressBlock(
                          color: Rb.orange,
                          edge: Rb.orangeEdge,
                          depth: 9,
                          radius: 16,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SignupScreen()),
                          ),
                          child: const SizedBox(
                            width: double.infinity,
                            child: Center(
                              child: BlockText('✨ SIGN UP — IT\'S FREE!',
                                  size: 19, stroke: 4.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
