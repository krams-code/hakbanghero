import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_colors.dart';
import '../main_shell.dart';
import '../character/character_creation_screen.dart';

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
  String? _gender; // 'male' | 'female'

  Future<void> _goHome() async {
  if (!mounted) return;

  final uid = FirebaseAuth.instance.currentUser?.uid;
  bool characterCreated = false;

  if (uid != null) {
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    characterCreated = doc.data()?['character_created'] as bool? ?? false;
  }

  if (!mounted) return;

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => characterCreated
          ? const MainShell()
          : const CharacterCreationScreen(),
    ),
    (_) => false,
  );
}

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _createUserDoc(User user, String username, {String? gender}) async {
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

      // ── New: character customization fields ─────────────────────
      'character_created': false,   // flips to true once they finish the creation flow
      'height_cm': null,
      'weight_kg': null,
      'skin_tone': '#E0AC69',       // default until they pick one
      'hair_style': 'short',        // default until they pick one
      'hair_color': '#1A1A1A',      // default until they pick one
      'body_tier': 'average',       // recalculated once height/weight are set
    });
  }
}

  Future<void> _signupEmail() async {
    final username = _usernameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (username.isEmpty || email.isEmpty || pass.isEmpty || _gender == null) {
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
        await _createUserDoc(cred.user!, username, gender: _gender);
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
      backgroundColor: AppColors.bgDeep,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios,
                      color: AppColors.textSub, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'CREATE ACCOUNT',
                style: TextStyle(
                  color: AppColors.blue,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Begin your hero journey',
                style: TextStyle(
                  color: AppColors.textSub,
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
                    color: AppColors.textSub,
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
                    color: AppColors.textSub,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              const SizedBox(height: 14),
              _buildGenderPicker(),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _signupEmail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    disabledBackgroundColor:
                        AppColors.blue.withOpacity(0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'CREATE HERO',
                          style: TextStyle(
                            color: Colors.white,
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
                  const Expanded(child: Divider(color: AppColors.borderDim)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or',
                        style: TextStyle(color: AppColors.textSub)),
                  ),
                  const Expanded(child: Divider(color: AppColors.borderDim)),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _signupGoogle,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.borderDim),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.g_mobiledata,
                      color: AppColors.blue, size: 22),
                  label: const Text(
                    'Sign up with Google',
                    style: TextStyle(
                      color: AppColors.textMain,
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
                        TextStyle(color: AppColors.textSub, fontSize: 13),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text(
                      'Login',
                      style: TextStyle(
                        color: AppColors.blue,
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
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderDim),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(color: AppColors.textMain, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textSub, fontSize: 14),
          prefixIcon: Icon(icon, color: AppColors.textSub, size: 20),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              vertical: 16, horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildGenderPicker() {
    Widget option(String value, String label, IconData icon) {
      final selected = _gender == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _gender = value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.blue.withOpacity(0.12)
                  : AppColors.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.blue : AppColors.borderDim,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(icon,
                    color: selected ? AppColors.blue : AppColors.textSub,
                    size: 22),
                const SizedBox(height: 6),
                Text(label,
                    style: TextStyle(
                        color: selected ? AppColors.blue : AppColors.textMain,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        option('male', 'Male', Icons.male),
        const SizedBox(width: 12),
        option('female', 'Female', Icons.female),
      ],
    );
  }
}