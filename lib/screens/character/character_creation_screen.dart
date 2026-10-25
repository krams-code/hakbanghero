import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'hero_picker_screen.dart' show saveErrorText;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/character_profile.dart';
import '../../models/hero_roster.dart';
import '../../widgets/hero_rig.dart';
import '../../widgets/block_inputs.dart';
import '../../widgets/block_ui.dart';
import '../../models/outfit_catalog.dart';
import '../../models/tutorial_progress.dart';
import '../main_shell.dart';
import '../../widgets/emoji_icons.dart';
import '../../state/user_doc.dart';

class CharacterCreationScreen extends StatefulWidget {
  final bool isEditMode; // true when opened from Profile to tweak appearance
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
  // Onboarding is locked to the starter pack: hair STYLE, expression and
  // clothes are not selectable here (see StarterPack). Only the body (from
  // height/weight), skin tone and hair colour are.
  HairStyle _hairStyle = HairStyle.wavyMane;
  String _hairColor = kHairColorPresets[0];

  String _heroId = kDefaultHeroId;

  bool _saving = false;
  bool _loadingExisting = true;

  /// 'male' | 'female' from sign-up (users/{uid}.gender). Picks the body sheet.
  String? _gender;

  @override
  void initState() {
    super.initState();
    _loadGender();
    if (widget.isEditMode) {
      _loadExistingProfile();
    } else {
      _loadingExisting = false;
    }
  }

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _genderSub;

  /// Follows users/{uid}.gender live: right after sign-up the doc may still
  /// be on its way, so a one-time read could miss the 'female' choice.
  void _loadGender() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    void apply(DocumentSnapshot<Map<String, dynamic>>? doc) {
      final data = doc?.data();
      if (data == null || !mounted) return;
      final g = genderKey(data['gender']);
      if (!_genderLoaded || (g != null && g != _gender && !_genderPickedHere)) {
        setState(() {
          _genderLoaded = true;
          _genderSaved = g != null;
          if (!_genderPickedHere) _gender = g;
        });
      }
    }
    apply(UserDoc.instance.snapshotFor(uid));
    _genderSub = UserDoc.instance.stream.listen(apply, onError: (_) {
      // keep the male default; never block hero creation on this
    });
  }

  /// Girl SPROUT art when the player picked FEMALE at sign-up.
  bool get _girl => genderKey(_gender) == 'female';

  /// The account doc has been read (so we know if a gender is saved).
  bool _genderLoaded = false;

  /// A gender is already saved (email sign-up asks for it).
  bool _genderSaved = false;

  /// Picked on this screen (Google sign-up never asks).
  bool _genderPickedHere = false;

  /// BOY / GIRL picker, shown only when the account has no gender yet.
  Widget _genderPicker() {
    Widget tile(String value, String label, Color c, Color e) {
      final sel = _gender == value;
      return Expanded(
        child: PressBlock(
          color: sel ? c : Rb.slot,
          edge: sel ? e : Rb.slateEdge,
          depth: 5,
          radius: 14,
          forcePressed: sel,
          padding: const EdgeInsets.symmetric(vertical: 14),
          onTap: () => setState(() {
            _gender = value;
            _genderPickedHere = true;
          }),
          child: Center(child: BlockText(label, size: 16, stroke: 4)),
        ),
      );
    }

    return Row(children: [
      tile('male', '\u2642 BOY', Rb.blue, Rb.blueEdge),
      const SizedBox(width: 10),
      tile('female', '\u2640 GIRL', const Color(0xFFFF5FA2), const Color(0xFF8A1F55)),
    ]);
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
    _genderSub?.cancel();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    blockSnack(context, msg);
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

    if (!widget.isEditMode && (heightCm == null || heightCm < 100 || heightCm > 250)) {
      _snack('Enter a height between 100 and 250 cm.');
      return;
    }
    if (!widget.isEditMode && (weightKg == null || weightKg < 25 || weightKg > 300)) {
      _snack('Enter a weight between 25 and 300 kg.');
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _snack('You need to be logged in.');
      return;
    }

    if (!widget.isEditMode && _genderLoaded && !_genderSaved && _gender == null) {
      _snack('Pick BOY or GIRL first.');
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
      final fields = profile.toFirestore();
      if (widget.isEditMode) {
        // weight and height only change through the weekly check-in
        fields
          ..remove('height_cm')
          ..remove('weight_kg')
          ..remove('body_tier');
      }
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        ...fields,
        if (!widget.isEditMode) ...{
          // creating the hero counts as the first weekly check-in
          'last_checkin_at': FieldValue.serverTimestamp(),
          // brand-new hero -> the free starter pack, nothing else
          ...StarterPack.toFirestore(),
          'hero_id': _heroId,
          'owned_heroes': FieldValue.arrayUnion([_heroId]),
          if (_genderPickedHere && _gender != null) 'gender': _gender,
          'owned_items': FieldValue.arrayUnion(StarterPack.ownedItems),
          // ...and show the onboarding tutorial once
          'tutorial_done': false,
          // Phase 2 (post-first-run walkthrough) still to come
          TutorialProgress.firstRunField: false,
        },
      });
      if (!widget.isEditMode && fields['weight_kg'] is num) {
        // first point of the weight chart (best effort)
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('weight_checkins')
            .add({
          'at': FieldValue.serverTimestamp(),
          'height_cm': fields['height_cm'],
          'weight_kg': fields['weight_kg'],
        }).catchError((_) => FirebaseFirestore.instance.collection('users').doc(uid));
      }

      if (!mounted) return;

      if (widget.isEditMode) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShell()),
          (_) => false,
        );
      }
    } catch (e) {
      debugPrint('character save failed: $e');
      _snack(saveErrorText(e, 'Failed to save character.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ───────────────────────── build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loadingExisting) {
      return const Scaffold(
        backgroundColor: Rb.bg,
        body: Center(child: CircularProgressIndicator(color: Rb.blue)),
      );
    }

    return PopScope(
      canPop: widget.isEditMode, // onboarding can't be skipped; editing can
      child: Scaffold(
        backgroundColor: Rb.bg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    const SizedBox(height: 16),
                    _viewport(),
                    const SizedBox(height: 22),
                    if (widget.isEditMode)
                      _panel('📏 BODY STATS', [
                        _label('UPDATED BY THE WEEKLY CHECK-IN'),
                        const SizedBox(height: 8),
                        Text(
                          'Your weight and height change once a week through the '
                          'check-in on your Profile. Here you only change how your hero looks.',
                          style: const TextStyle(
                              color: Color(0xFFD0D5DB),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800),
                        ),
                      ])
                    else
                      _panel('📏 BODY STATS', [
                        _label('UNITS'),
                        _unitToggle(),
                        const SizedBox(height: 16),
                        _isMetric ? _metricHeightField() : _imperialHeightFields(),
                        const SizedBox(height: 16),
                        _weightField(),
                      ]),
                    const SizedBox(height: 16),
                    if (!widget.isEditMode && _genderLoaded && !_genderSaved) ...[
                      _panel('\u{1F9D1} ARE YOU A BOY OR A GIRL?', [
                        _label('YOUR HERO AND THE BOYS / GIRLS BOARD USE THIS'),
                        const SizedBox(height: 8),
                        _genderPicker(),
                      ]),
                      const SizedBox(height: 16),
                    ],
                    if (!widget.isEditMode) ...[
                      _panel('🎭 CHOOSE YOUR COSTUME', [
                        _label('YOU CAN UNLOCK MORE COSTUMES LATER'),
                        const SizedBox(height: 8),
                        _heroChoices(),
                      ]),
                    ],
                    const SizedBox(height: 24),
                    NeonBlueButton(
                      label: widget.isEditMode ? 'SAVE CHANGES' : 'BEGIN YOUR JOURNEY',
                      loading: _saving,
                      onTap: _saveAndContinue,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroChoices() => Row(
        children: [
          for (final h in kHeroes.where((x) => x.starter))
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: PressBlock(
                  color: _heroId == h.id ? Rb.gold : h.color,
                  edge: _heroId == h.id ? Rb.goldEdge : h.edge,
                  depth: 4,
                  radius: 12,
                  padding: const EdgeInsets.all(6),
                  onTap: () => setState(() => _heroId = h.id),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 84,
                        child: HeroStill(
                            heroId: h.id,
                            tier: _previewProfile.bodyTier,
                            girl: _girl),
                      ),
                      const SizedBox(height: 4),
                      BlockText(h.name, size: 11, stroke: 3),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );

  Widget _header() => Block(
        color: Rb.hud,
        edge: Rb.hudEdge,
        depth: 6,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            if (widget.isEditMode) ...[
              PressBlock(
                color: const Color(0xFFE2E2E2),
                edge: const Color(0xFF6B6B6B),
                depth: 4,
                radius: 12,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                onTap: () => Navigator.of(context).pop(),
                child: const EmojiText('◀',
                    style: TextStyle(
                        color: Color(0xFF232527),
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: BlockText(
                      widget.isEditMode ? '✏️ CUSTOMIZE HERO' : '🧑 CREATE YOUR HERO',
                      size: 20,
                      stroke: 4.5,
                    ),
                  ),
                  const Text(
                    'Your body reflects your real stats',
                    style: TextStyle(
                      color: Color(0xFF2A2D31),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // Live preview: rounded-square sky block, 3px black border, hard 3D shadow.
  Widget _viewport() {
    final p = _previewProfile;
    return Column(
      children: [
        Container(
          height: 340,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF8FD0FF),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.black, width: 3),
            boxShadow: const [
              BoxShadow(color: Colors.black, offset: Offset(0, 8), blurRadius: 0),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: 34,
                    decoration: const BoxDecoration(
                      color: Color(0xFF5BBF5B),
                      border: Border(top: BorderSide(color: Colors.black, width: 3)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 22),
                  child: Center(
                    child: HeroRig(
                      heroId: _heroId,
                      tier: p.bodyTier,
                      pose: RigPose.idle,
                      girl: _girl,
                      height: 290,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Block(
          color: Rb.gold,
          edge: Rb.goldEdge,
          depth: 4,
          radius: 10,
          gloss: true,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: BlockText('💪 ${p.bodyTier.label.toUpperCase()}', size: 12, stroke: 3.5),
        ),
      ],
    );
  }

  Widget _panel(String title, List<Widget> children) => Block(
        color: Rb.panel,
        edge: Rb.panelEdge,
        depth: 6,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BlockText(title, size: 15, stroke: 4),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: BlockText(text, size: 12, stroke: 3.5),
      );

  // ── unit toggle: the active side is physically pressed down ──
  Widget _unitToggle() {
    Widget option(String label, bool metric) {
      final selected = _isMetric == metric;
      return Expanded(
        child: PressBlock(
          color: selected ? Rb.blue : const Color(0xFFE2E4E7),
          edge: selected ? Rb.blueEdge : const Color(0xFF6B6F75),
          depth: 6,
          radius: 14,
          forcePressed: selected,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          onTap: () => setState(() => _isMetric = metric),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: BlockText(label, size: 11, stroke: 3.5),
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

  Widget _unit(String t) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: BlockText(t, size: 12, stroke: 3, color: const Color(0xFFB8BDC4)),
      );

  Widget _metricHeightField() => BlockTextField(
        label: 'HEIGHT',
        hint: 'e.g. 170',
        icon: '📏',
        controller: _heightCmCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        suffix: _unit('cm'),
      );

  Widget _imperialHeightFields() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: BlockTextField(
              label: 'HEIGHT (FT)',
              hint: '5',
              icon: '📏',
              controller: _heightFtCtrl,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              suffix: _unit('ft'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: BlockTextField(
              label: '(IN)',
              hint: '8',
              icon: '📏',
              controller: _heightInCtrl,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              suffix: _unit('in'),
            ),
          ),
        ],
      );

  Widget _weightField() => BlockTextField(
        label: 'WEIGHT',
        hint: _isMetric ? 'e.g. 65' : 'e.g. 143',
        icon: '⚖️',
        controller: _weightCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        suffix: _unit(_isMetric ? 'kg' : 'lbs'),
      );

}
