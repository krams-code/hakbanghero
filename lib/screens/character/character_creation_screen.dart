import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/character_profile.dart';
import '../../widgets/avatar_layer_stack.dart' show kSpriteWidth, kSpriteHeight;
import '../../widgets/avatar_preview.dart';
import '../../widgets/block_inputs.dart';
import '../../widgets/block_ui.dart';
import '../../models/outfit_catalog.dart';
import '../../models/tutorial_progress.dart';
import '../main_shell.dart';

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

  Future<void> _loadGender() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final g = doc.data()?['gender'] as String?;
      if (mounted && g != _gender) setState(() => _gender = g);
    } catch (_) {
      // keep the male default; never block hero creation on this
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

    if (heightCm == null || heightCm < 100 || heightCm > 250) {
      _snack('Enter a height between 100 and 250 cm.');
      return;
    }
    if (weightKg == null || weightKg < 25 || weightKg > 300) {
      _snack('Enter a weight between 25 and 300 kg.');
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
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        ...profile.toFirestore(),
        if (!widget.isEditMode) ...{
          // brand-new hero -> the free starter pack, nothing else
          ...StarterPack.toFirestore(),
          'owned_items': FieldValue.arrayUnion(StarterPack.ownedItems),
          // ...and show the onboarding tutorial once
          'tutorial_done': false,
          // Phase 2 (post-first-run walkthrough) still to come
          TutorialProgress.firstRunField: false,
        },
      });

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
      _snack('Failed to save character. Try again.');
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
                    _panel('📏 BODY STATS', [
                      _label('UNITS'),
                      _unitToggle(),
                      const SizedBox(height: 16),
                      _isMetric ? _metricHeightField() : _imperialHeightFields(),
                      const SizedBox(height: 16),
                      _weightField(),
                    ]),
                    const SizedBox(height: 16),
                    _panel('🎨 LOOK', [
                      _label('SKIN TONE'),
                      _swatchRow(kSkinTonePresets, _skinTone,
                          (hex) => setState(() => _skinTone = hex)),
                      const SizedBox(height: 18),
                      _label('HAIR COLOR'),
                      _swatchRow(_hairColorChoices, _hairColor,
                          (hex) => setState(() => _hairColor = hex)),
                      const SizedBox(height: 18),
                      _starterPackNote(),
                    ]),
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
                child: const Text('◀',
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
                  padding: const EdgeInsets.only(top: 10, bottom: 18),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    clipBehavior: Clip.none,
                    child: SizedBox(
                      width: kSpriteWidth,
                      height: kSpriteHeight + 44, // headroom for tall hair
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: 0,
                            top: 44,
                            width: kSpriteWidth,
                            height: kSpriteHeight,
                            child: AvatarPreview(
                              bodySize: p.bodyTier.id,
                              expression: p.faceExpression.id,
                              hairStyle: p.hairStyle.id,
                              activeGear: StarterPack.activeOutfit,
                              skinTone: p.skinTone,
                              hairColor: p.hairColor,
                              filterQuality: FilterQuality.none,
                              gender: _gender,
                            ),
                          ),
                        ],
                      ),
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

  // ── swatches: rounded-square tiles that bounce when tapped ──
  Widget _swatchRow(List<String> hexList, String selected, ValueChanged<String> onPick) {
    return Wrap(
      spacing: 12,
      runSpacing: 14,
      children: [
        for (final hex in hexList)
          _BounceTile(
            selected: hex == selected,
            onTap: () => onPick(hex),
            child: ColoredBox(color: _colorFromHex(hex)),
          ),
      ],
    );
  }

  /// Hair colours offered here: the free presets (Black, Brown, Blonde).
  /// When editing, the colour the hero already wears stays available too.
  /// Everything else is bought in the Shop.
  List<String> get _hairColorChoices => widget.isEditMode
      ? <String>{...StarterPack.hairColors, _hairColor}.toList()
      : StarterPack.hairColors;

  /// Hair style / expression / clothes are locked to the starter set.
  Widget _starterPackNote() => Block(
        color: Rb.slate,
        edge: Rb.slateEdge,
        depth: 4,
        radius: 12,
        padding: const EdgeInsets.all(10),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BlockText('🎁 STARTER PACK', size: 12, stroke: 3.5, color: Rb.gold),
            SizedBox(height: 4),
            BlockText(
              'Wavy Mane hair • Default face • Training outfit.\n'
              'Unlock more styles in the 🛒 Shop and on the Milestone path!',
              size: 10,
              stroke: 2.5,
              color: Color(0xFFB8BDC4),
            ),
          ],
        ),
      );

  Color _colorFromHex(String hex) =>
      Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
}

/// Thick rounded-square tile: 3px black border + hard bottom shadow.
/// Bounces on tap; the selected tile sits pushed down with a gold ring + ✔.
class _BounceTile extends StatefulWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final double? size; // null = fills the width, square

  const _BounceTile({
    required this.selected,
    required this.onTap,
    required this.child,
    this.size = 48,
  });

  @override
  State<_BounceTile> createState() => _BounceTileState();
}

class _BounceTileState extends State<_BounceTile> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260));

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.88), weight: 25),
    TweenSequenceItem(
        tween: Tween(begin: 0.88, end: 1.14).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40),
    TweenSequenceItem(
        tween: Tween(begin: 1.14, end: 1.0).chain(CurveTween(curve: Curves.bounceOut)),
        weight: 35),
  ]).animate(_c);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;

    Widget tile = Container(
      margin: EdgeInsets.only(top: sel ? 4 : 0, bottom: sel ? 0 : 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sel ? Rb.gold : Colors.black, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black,
            offset: Offset(0, sel ? 0 : 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (sel)
              const Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: EdgeInsets.all(2),
                  child: BlockText('✔', size: 14, stroke: 3.5),
                ),
              ),
          ],
        ),
      ),
    );

    tile = widget.size == null
        ? AspectRatio(aspectRatio: 0.8, child: tile)
        : SizedBox(width: widget.size, height: widget.size! + 4, child: tile);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _c.forward(from: 0);
        widget.onTap();
      },
      child: ScaleTransition(scale: _scale, child: tile),
    );
  }
}
