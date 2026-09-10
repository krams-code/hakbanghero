import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/character_profile.dart';
import '../../widgets/character_avatar_widget.dart';
import '../../theme/app_colors.dart';
import '../main_shell.dart';

class CharacterCreationScreen extends StatefulWidget {
  final bool isEditMode; // true when opened from Equipment to tweak appearance
  const CharacterCreationScreen({super.key, this.isEditMode = false});

  @override
  State<CharacterCreationScreen> createState() => _CharacterCreationScreenState();
}

class _CharacterCreationScreenState extends State<CharacterCreationScreen> {
  bool _isMetric = true;

  final _heightCmCtrl = TextEditingController();
  final _heightFtCtrl = TextEditingController();
  final _heightInCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();

  String _skinTone = kSkinTonePresets[2];
  HairStyle _hairStyle = HairStyle.short;
  String _hairColor = kHairColorPresets[0];

  bool _saving = false;
  bool _loadingExisting = true;

  @override
  void initState() {
    super.initState();
    if (widget.isEditMode) {
      _loadExistingProfile();
    } else {
      _loadingExisting = false;
    }
  }

  Future<void> _loadExistingProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loadingExisting = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      if (data != null && mounted) {
        final profile = CharacterProfile.fromFirestore(data);
        setState(() {
          if (profile.heightCm != null) _heightCmCtrl.text = profile.heightCm!.toStringAsFixed(0);
          if (profile.weightKg != null) _weightCtrl.text = profile.weightKg!.toStringAsFixed(0);
          _skinTone = profile.skinTone;
          _hairStyle = profile.hairStyle;
          _hairColor = profile.hairColor;
          _loadingExisting = false;
        });
      } else if (mounted) {
        setState(() => _loadingExisting = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  @override
  void dispose() {
    _heightCmCtrl.dispose();
    _heightFtCtrl.dispose();
    _heightInCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  double? get _heightCm {
    if (_isMetric) {
      return double.tryParse(_heightCmCtrl.text.trim());
    } else {
      final ft = double.tryParse(_heightFtCtrl.text.trim()) ?? 0;
      final inch = double.tryParse(_heightInCtrl.text.trim()) ?? 0;
      if (ft == 0 && inch == 0) return null;
      return (ft * 30.48) + (inch * 2.54);
    }
  }

  double? get _weightKg {
    final val = double.tryParse(_weightCtrl.text.trim());
    if (val == null) return null;
    return _isMetric ? val : val * 0.453592;
  }

  CharacterProfile get _previewProfile => CharacterProfile(
        heightCm: _heightCm,
        weightKg: _weightKg,
        skinTone: _skinTone,
        hairStyle: _hairStyle,
        hairColor: _hairColor,
      );

  Future<void> _saveAndContinue() async {
    final heightCm = _heightCm;
    final weightKg = _weightKg;

    if (heightCm == null || heightCm <= 0) {
      _snack('Please enter your height.');
      return;
    }
    if (weightKg == null || weightKg <= 0) {
      _snack('Please enter your weight.');
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _snack('You need to be logged in.');
      return;
    }

    setState(() => _saving = true);

    final profile = CharacterProfile(
      heightCm: heightCm,
      weightKg: weightKg,
      skinTone: _skinTone,
      hairStyle: _hairStyle,
      hairColor: _hairColor,
      created: true,
    );

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update(profile.toFirestore());

      if (!mounted) return;

      if (widget.isEditMode) {
        Navigator.of(context).pop(); // just return to Equipment screen
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShell()),
          (_) => false,
        );
      }
    } catch (e) {
      _snack('Failed to save character. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingExisting) {
      return const Scaffold(
        backgroundColor: AppColors.bgDeep,
        body: Center(child: CircularProgressIndicator(color: AppColors.blue)),
      );
    }

    return PopScope(
      canPop: widget.isEditMode, // full onboarding flow can't be skipped; editing later can
      child: Scaffold(
        backgroundColor: AppColors.bgDeep,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.isEditMode)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios, color: AppColors.textSub, size: 18),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                Text(
                  widget.isEditMode ? 'CUSTOMIZE APPEARANCE' : 'CREATE YOUR HERO',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.blue,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Your body reflects your real stats — customize the rest',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSub, fontSize: 12),
                ),
                const SizedBox(height: 24),

                // ── Live preview ──────────────────────────────────
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.bgCard,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.borderDim),
                    ),
                    child: CharacterAvatarWidget(profile: _previewProfile),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _previewProfile.bodyTier.label.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),

                const SizedBox(height: 28),
                _sectionLabel('UNITS'),
                const SizedBox(height: 8),
                _unitToggle(),

                const SizedBox(height: 20),
                _sectionLabel('HEIGHT'),
                const SizedBox(height: 8),
                _isMetric ? _metricHeightField() : _imperialHeightFields(),

                const SizedBox(height: 20),
                _sectionLabel('WEIGHT'),
                const SizedBox(height: 8),
                _weightField(),

                const SizedBox(height: 24),
                _sectionLabel('SKIN TONE'),
                const SizedBox(height: 10),
                _swatchRow(
                  kSkinTonePresets,
                  _skinTone,
                  (hex) => setState(() => _skinTone = hex),
                ),

                const SizedBox(height: 24),
                _sectionLabel('HAIRSTYLE'),
                const SizedBox(height: 10),
                _hairStyleRow(),

                const SizedBox(height: 24),
                _sectionLabel('HAIR COLOR'),
                const SizedBox(height: 10),
                _swatchRow(
                  kHairColorPresets,
                  _hairColor,
                  (hex) => setState(() => _hairColor = hex),
                ),

                const SizedBox(height: 32),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveAndContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            widget.isEditMode ? 'SAVE CHANGES' : 'BEGIN YOUR JOURNEY',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          color: AppColors.textSub,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      );

  Widget _unitToggle() {
    Widget option(String label, bool metric) {
      final selected = _isMetric == metric;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _isMetric = metric),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.blue.withOpacity(0.15) : AppColors.bgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? AppColors.blue : AppColors.borderDim,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? AppColors.blue : AppColors.textSub,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        option('METRIC (cm / kg)', true),
        const SizedBox(width: 10),
        option('IMPERIAL (ft-in / lbs)', false),
      ],
    );
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textSub, fontSize: 14),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      );

  Widget _fieldWrapper({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderDim),
        ),
        child: child,
      );

  Widget _metricHeightField() {
    return _fieldWrapper(
      child: TextField(
        controller: _heightCmCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: AppColors.textMain),
        decoration: _fieldDecoration('Height in cm (e.g. 170)'),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _imperialHeightFields() {
    return Row(
      children: [
        Expanded(
          child: _fieldWrapper(
            child: TextField(
              controller: _heightFtCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.textMain),
              decoration: _fieldDecoration('Feet'),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _fieldWrapper(
            child: TextField(
              controller: _heightInCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.textMain),
              decoration: _fieldDecoration('Inches'),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
      ],
    );
  }

  Widget _weightField() {
    return _fieldWrapper(
      child: TextField(
        controller: _weightCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: AppColors.textMain),
        decoration: _fieldDecoration(
          _isMetric ? 'Weight in kg (e.g. 65)' : 'Weight in lbs (e.g. 143)',
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _swatchRow(List<String> hexList, String selected, ValueChanged<String> onPick) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: hexList.map((hex) {
        final isSelected = hex == selected;
        final color = _colorFromHex(hex);
        return GestureDetector(
          onTap: () => onPick(hex),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? AppColors.blue : AppColors.borderDim,
                width: isSelected ? 3 : 1,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: AppColors.blue.withOpacity(0.4), blurRadius: 8)]
                  : [],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _hairStyleRow() {
    return Row(
      children: HairStyle.values.map((style) {
        final selected = _hairStyle == style;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _hairStyle = style),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: selected ? AppColors.blue.withOpacity(0.15) : AppColors.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? AppColors.blue : AppColors.borderDim,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.face,
                    color: selected ? AppColors.blue : AppColors.textSub,
                    size: 20,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    style.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected ? AppColors.blue : AppColors.textSub,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Color _colorFromHex(String hex) {
    final cleaned = hex.replaceAll('#', '');
    return Color(int.parse('FF$cleaned', radix: 16));
  }
}