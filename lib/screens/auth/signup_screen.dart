import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../utils/password_rules.dart';
import '../../widgets/block_inputs.dart';
import '../../widgets/block_ui.dart';
import '../character/character_creation_screen.dart';
import '../main_shell.dart';
import '../../models/outfit_catalog.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _submitted = false; // show field errors only after the first attempt
  /// The hero type picked on this screen: 'male' | 'female' (null until chosen).
  /// Saved to users/{uid}.gender and used to route the avatar's body sprites.
  String? selectedGender;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');
  static final _nameRe = RegExp(r'^[A-Za-z0-9_ ]{3,16}$');

  // ── validation ───────────────────────────────────────────────────────
  String? get _nameError {
    final v = _usernameCtrl.text.trim();
    if (v.isEmpty) return 'Pick a hero name';
    if (!_nameRe.hasMatch(v)) return '3-16 letters, numbers, _ or spaces';
    return null;
  }

  String? get _emailError {
    final v = _emailCtrl.text.trim();
    if (v.isEmpty) return 'Enter your email';
    if (!_emailRe.hasMatch(v)) return 'That email looks invalid';
    return null;
  }

  String? get _passError =>
      PasswordRules.isStrong(_passCtrl.text) ? null : 'Meet all the password rules below';

  String? get _confirmError {
    if (_confirmCtrl.text.isEmpty) return 'Re-enter your password';
    if (_confirmCtrl.text != _passCtrl.text) return 'Passwords do not match';
    return null;
  }

  bool get _valid =>
      _nameError == null &&
      _emailError == null &&
      _passError == null &&
      _confirmError == null &&
      selectedGender != null;

  // ── flow ─────────────────────────────────────────────────────────────
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

  Future<void> _createUserDoc(User user, String username, {String? gender}) async {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (!doc.exists) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'username': username,
        'email': user.email,
        'gender': gender,
        'level': 1,
        'xp': 0,
        'coins': 100,
        'gems': 10,
        'heroic_souls': 0,
        'total_km': 0.0,
        'total_steps': 0,
        'total_sessions': 0,
        'created_at': FieldValue.serverTimestamp(),
        'character_created': false,
        'height_cm': null,
        'weight_kg': null,
        'skin_tone': '#E0AC69',
        // Starter pack: every new hero starts with ONLY these free items
        // (Wavy Mane, default face, white tank-top set).
        ...StarterPack.toFirestore(),
        'owned_items': StarterPack.ownedItems,
        'hair_color': '#1A1A1A',
        'body_tier': 'average',
      });
    }
  }

  Future<void> _signupEmail() async {
    setState(() => _submitted = true);
    if (!_valid) {
      _snack(selectedGender == null
          ? 'Pick your hero type and fix the red fields.'
          : 'Fix the red fields to continue.');
      return;
    }

    final username = _usernameCtrl.text.trim();
    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text, // never trimmed
      );
      if (cred.user != null) {
        await cred.user!.updateDisplayName(username);
        await _createUserDoc(cred.user!, username, gender: selectedGender);
        _goHome();
      }
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? 'Sign up failed.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signupGoogle() async {
    setState(() => _loading = true);
    try {
      final cred =
          await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      if (cred.user == null) return;
      await _createUserDoc(cred.user!, cred.user!.displayName ?? 'Hero');
      _goHome();
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? 'Google sign-up failed.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ── UI ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Rb.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PressBlock(
                      color: const Color(0xFFE2E2E2),
                      edge: const Color(0xFF6B6B6B),
                      depth: 4,
                      radius: 12,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      onTap: () => Navigator.pop(context),
                      child: const Text('◀',
                          style: TextStyle(
                              color: Color(0xFF232527),
                              fontSize: 16,
                              fontWeight: FontWeight.w900)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const AuthBanner(
                    title: 'CREATE ACCOUNT',
                    subtitle: 'BEGIN YOUR HERO JOURNEY',
                  ),
                  const SizedBox(height: 22),
                  Block(
                    color: Rb.panel,
                    edge: Rb.panelEdge,
                    depth: 6,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        BlockTextField(
                          label: 'HERO NAME',
                          hint: 'e.g. SwiftRunner',
                          icon: '🧑',
                          controller: _usernameCtrl,
                          action: TextInputAction.next,
                          onChanged: (_) => setState(() {}),
                          error: _submitted ? _nameError : null,
                        ),
                        const SizedBox(height: 16),
                        BlockTextField(
                          label: 'EMAIL',
                          hint: 'hero@email.com',
                          icon: '✉️',
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          action: TextInputAction.next,
                          onChanged: (_) => setState(() {}),
                          error: _submitted ? _emailError : null,
                        ),
                        const SizedBox(height: 16),
                        BlockTextField(
                          label: 'PASSWORD',
                          hint: 'Make it strong!',
                          icon: '🔒',
                          controller: _passCtrl,
                          obscure: _obscure,
                          action: TextInputAction.next,
                          onChanged: (_) => setState(() {}),
                          error: _submitted ? _passError : null,
                          suffix: _eye(_obscure, () => setState(() => _obscure = !_obscure)),
                        ),
                        const SizedBox(height: 12),
                        _strengthMeter(),
                        const SizedBox(height: 16),
                        BlockTextField(
                          label: 'CONFIRM PASSWORD',
                          hint: 'Type it again',
                          icon: '🔁',
                          controller: _confirmCtrl,
                          obscure: _obscureConfirm,
                          action: TextInputAction.done,
                          onChanged: (_) => setState(() {}),
                          error: (_submitted || _confirmCtrl.text.isNotEmpty)
                              ? _confirmError
                              : null,
                          suffix: _eye(_obscureConfirm,
                              () => setState(() => _obscureConfirm = !_obscureConfirm)),
                        ),
                        const SizedBox(height: 18),
                        const Padding(
                          padding: EdgeInsets.only(left: 4, bottom: 6),
                          child: BlockText('HERO TYPE', size: 12, stroke: 3.5),
                        ),
                        Row(
                          children: [
                            Expanded(child: _genderTile('male', '♂ MALE')),
                            const SizedBox(width: 10),
                            Expanded(child: _genderTile('female', '♀ FEMALE')),
                          ],
                        ),
                        if (_submitted && selectedGender == null)
                          const Padding(
                            padding: EdgeInsets.only(left: 4, top: 8),
                            child: BlockText('⚠ Choose a hero type',
                                size: 11, stroke: 3, color: Color(0xFFFF8A80)),
                          ),
                        const SizedBox(height: 22),
                        NeonBlueButton(
                          label: 'CREATE HERO',
                          loading: _loading,
                          onTap: _signupEmail,
                        ),
                        const SizedBox(height: 16),
                        PressBlock(
                          color: const Color(0xFFF2F3F5),
                          edge: const Color(0xFF6B6F75),
                          depth: 5,
                          radius: 14,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          onTap: _loading ? null : _signupGoogle,
                          child: const SizedBox(
                            width: double.infinity,
                            child: Center(
                              child: BlockText('G  SIGN UP WITH GOOGLE',
                                  size: 13, stroke: 3.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  PressBlock(
                    color: Rb.slot,
                    edge: Rb.slateEdge,
                    depth: 5,
                    radius: 14,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    onTap: () => Navigator.pop(context),
                    child: const SizedBox(
                      width: double.infinity,
                      child: Center(
                        child: BlockText('ALREADY A HERO? LOGIN',
                            size: 13, stroke: 3.5),
                      ),
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

  Widget _eye(bool obscured, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(obscured ? '🙈' : '👁️', style: const TextStyle(fontSize: 20)),
        ),
      );

  /// Live checklist + 6-segment power bar.
  Widget _strengthMeter() {
    final pass = _passCtrl.text;
    final done = PasswordRules.passed(pass);
    final total = PasswordRules.all.length;
    final color = done <= 2
        ? Rb.red
        : done <= 4
            ? Rb.orange
            : done < total
                ? Rb.gold
                : Rb.neon;
    final word = pass.isEmpty
        ? 'EMPTY'
        : done <= 2
            ? 'WEAK'
            : done <= 4
                ? 'OKAY'
                : done < total
                    ? 'ALMOST'
                    : 'LEGENDARY';

    return Block(
      color: Rb.slate,
      edge: Rb.slateEdge,
      depth: 4,
      radius: 12,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BlockText('🛡 PASSWORD POWER', size: 11, stroke: 3),
              const Spacer(),
              BlockText(word, size: 11, stroke: 3, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < total; i++)
                Expanded(
                  child: Container(
                    height: 12,
                    margin: EdgeInsets.only(right: i == total - 1 ? 0 : 4),
                    decoration: BoxDecoration(
                      color: i < done ? color : const Color(0xFF3A3D40),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (final r in PasswordRules.all)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  BlockText(r.test(pass) ? '✔' : '✖',
                      size: 11,
                      stroke: 2.5,
                      color: r.test(pass) ? Rb.neon : const Color(0xFFFF8A80)),
                  const SizedBox(width: 8),
                  BlockText(r.label,
                      size: 11,
                      stroke: 2.5,
                      color: r.test(pass) ? Colors.white : const Color(0xFFB8BDC4)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _genderTile(String value, String label) {
    final sel = selectedGender == value;
    return PressBlock(
      color: sel ? Rb.gold : Rb.slot,
      edge: sel ? Rb.goldEdge : Rb.slateEdge,
      depth: 6,
      radius: 14,
      forcePressed: sel,
      padding: const EdgeInsets.symmetric(vertical: 14),
      onTap: () => setState(() => selectedGender = value),
      child: Center(child: BlockText(label, size: 14, stroke: 3.5)),
    );
  }
}
