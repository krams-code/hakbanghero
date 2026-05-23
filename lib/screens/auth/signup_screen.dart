import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main_shell.dart';

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

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (_) => false,
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _createUserDoc(User user, String username) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (!doc.exists) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'username': username,
        'email': user.email,
        'level': 1,
        'xp': 0,
        'coins': 100,
        'gems': 10,
        'heroic_souls': 0,
        'total_km': 0.0,
        'total_steps': 0,
        'total_sessions': 0,
        'created_at': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _signupEmail() async {
    final username = _usernameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (username.isEmpty || email.isEmpty || pass.isEmpty) {
      _snack('Please fill in all fields.');
      return;
    }
    if (pass != confirm) {
      _snack('Passwords do not match.');
      return;
    }
    if (pass.length < 6) {
      _snack('Password must be at least 6 characters.');
      return;
    }

    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: pass,
      );
      if (cred.user != null) {
        await cred.user!.updateDisplayName(username);
        await _createUserDoc(cred.user!, username);
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
      final cred = await FirebaseAuth.instance
          .signInWithPopup(GoogleAuthProvider());
      if (cred.user == null) return;
      await _createUserDoc(
          cred.user!, cred.user!.displayName ?? 'Hero');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060C06),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Back button
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios,
                      color: Color(0xFF4A8A4A), size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'CREATE ACCOUNT',
                style: TextStyle(
                  color: Color(0xFF00FF41),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Begin your hero journey',
                style: TextStyle(
                  color: Color(0xFF4A7A4A),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 32),
              _buildField(
                controller: _usernameCtrl,
                hint: 'Hero Name',
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 14),
              _buildField(
                controller: _emailCtrl,
                hint: 'Email',
                icon: Icons.email_outlined,
              ),
              const SizedBox(height: 14),
              _buildField(
                controller: _passCtrl,
                hint: 'Password',
                icon: Icons.lock_outline,
                obscure: _obscure,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    color: const Color(0xFF4A8A4A),
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              const SizedBox(height: 14),
              _buildField(
                controller: _confirmCtrl,
                hint: 'Confirm Password',
                icon: Icons.lock_outline,
                obscure: _obscureConfirm,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_off
                        : Icons.visibility,
                    color: const Color(0xFF4A8A4A),
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _signupEmail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FF41),
                    disabledBackgroundColor:
                        const Color(0xFF00FF41).withOpacity(0.5),
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
                          'CREATE HERO',
                          style: TextStyle(
                            color: Color(0xFF0A0F0A),
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                      child: Divider(color: const Color(0xFF1A3A1A))),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or',
                        style: TextStyle(color: Color(0xFF3A6A3A))),
                  ),
                  Expanded(
                      child: Divider(color: const Color(0xFF1A3A1A))),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _signupGoogle,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1A4A1A)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.g_mobiledata,
                      color: Color(0xFF00FF41), size: 22),
                  label: const Text(
                    'Sign up with Google',
                    style: TextStyle(
                      color: Color(0xFFD0EED0),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Already have an account? ',
                    style:
                        TextStyle(color: Color(0xFF4A7A4A), fontSize: 13),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text(
                      'Login',
                      style: TextStyle(
                        color: Color(0xFF00FF41),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A0D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1A3A1A)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(color: Color(0xFFD0EED0), fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF3A6A3A), fontSize: 14),
          prefixIcon: Icon(icon, color: const Color(0xFF4A8A4A), size: 20),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              vertical: 16, horizontal: 16),
        ),
      ),
    );
  }
}