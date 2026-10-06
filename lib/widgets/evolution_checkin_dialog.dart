import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/body_composition.dart';
import '../models/character_profile.dart';
import '../state/evolution_state.dart';
import 'block_ui.dart';
import 'hero_sprite.dart';

/// Open the weekly / monthly weight check-in. Resolves to the result when the
/// player locked in a change, or null when they closed the dialog.
///
///   final r = await showEvolutionCheckIn(context);
///   if (r != null && r.improved) { ... }
Future<EvolutionResult?> showEvolutionCheckIn(BuildContext context) {
  return showGeneralDialog<EvolutionResult>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close check-in',
    barrierColor: Colors.black.withValues(alpha: 0.78),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => const EvolutionCheckInDialog(),
    transitionBuilder: (_, anim, __, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        child: child,
      ),
    ),
  );
}

const Color _kSky = Color(0xFF8FD0FF);
const Color _kGrass = Color(0xFF58B947);
const Color _kMuted = Color(0xFFB8C0CC);

/// Roblox-block modal: type your new weight + height, watch the hero's body
/// preview change live, then LOCK IN to evolve the avatar everywhere.
class EvolutionCheckInDialog extends StatefulWidget {
  const EvolutionCheckInDialog({super.key});

  @override
  State<EvolutionCheckInDialog> createState() => _EvolutionCheckInDialogState();
}

class _EvolutionCheckInDialogState extends State<EvolutionCheckInDialog>
    with SingleTickerProviderStateMixin {
  final EvolutionState _svc = EvolutionState.instance;

  late final BodyCompositionState _before; // form when the dialog opened
  late final Map<String, dynamic> _data; // hero look (skin/hair/outfit)
  late final double? _beforeBmi;
  late final AnimationController _shake;

  final TextEditingController _weightCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController();

  UnitSystem _unit = UnitSystem.metric;

  // Derived from the two text fields by _recompute().
  BodyCompositionState? _after;
  double? _bmi;
  double? _kg;
  double? _cm;
  String? _weightError;
  String? _heightError;
  bool _wasImproved = false;

  bool _saving = false;
  bool _locked = false;
  String? _saveError;
  bool _precached = false;

  @override
  void initState() {
    super.initState();
    _data = _svc.userData;
    _before = _svc.composition.value;
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );

    final h = (_data['height_cm'] as num?)?.toDouble();
    final w = (_data['weight_kg'] as num?)?.toDouble();
    _beforeBmi = (h != null && w != null && h > 0 && w > 0)
        ? calculateBmi(w, h)
        : null;
    if (w != null && w > 0) _weightCtrl.text = formatNumber(w);
    if (h != null && h > 0) _heightCtrl.text = formatNumber(h);
    _recompute(animate: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached) {
      _precached = true;
      // Insurance: the shell already did this, but it is cheap and makes the
      // live preview swap instantly even if the dialog opens very early.
      _svc.precacheBodies(context);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  // ───────────────────────── logic ─────────────────────────

  double? _readHeight() => _unit == UnitSystem.imperial
      ? parseImperialHeightInches(_heightCtrl.text)
      : parseNumber(_heightCtrl.text);

  /// Re-derive everything from the text fields. Call inside setState().
  void _recompute({bool animate = true}) {
    final wText = _weightCtrl.text.trim();
    final hText = _heightCtrl.text.trim();
    final w = parseNumber(wText);
    final h = _readHeight();

    String? we;
    String? he;
    if (wText.isNotEmpty) {
      if (w == null) {
        we = 'Numbers only';
      } else {
        final kg = _unit.weightToKg(w);
        if (kg < kMinWeightKg || kg > kMaxWeightKg) {
          we = '${_unit.kgToWeight(kMinWeightKg).round()}-'
              '${_unit.kgToWeight(kMaxWeightKg).round()} ${_unit.weightUnit}';
        }
      }
    }
    if (hText.isNotEmpty) {
      if (h == null) {
        he = _unit == UnitSystem.imperial ? "Try 5'8 or 68" : 'Numbers only';
      } else {
        final cm = _unit.heightToCm(h);
        if (cm < kMinHeightCm || cm > kMaxHeightCm) {
          he = '${_unit.cmToHeight(kMinHeightCm).round()}-'
              '${_unit.cmToHeight(kMaxHeightCm).round()} ${_unit.heightUnit}';
        }
      }
    }
    _weightError = we;
    _heightError = he;

    final prevAfter = _after;
    if (w != null && h != null && we == null && he == null) {
      _after = calculateBodyComposition(w, h, unit: _unit);
      _bmi = calculateBmi(w, h, unit: _unit);
      _kg = _unit.weightToKg(w);
      _cm = _unit.heightToCm(h);
    } else {
      _after = null;
      _bmi = null;
      _kg = null;
      _cm = null;
    }

    final improved = _after != null && _after!.improvesOn(_before);
    if (animate && improved && (!_wasImproved || prevAfter != _after)) {
      _celebrate();
    }
    _wasImproved = improved;
  }

  void _celebrate() {
    HapticFeedback.mediumImpact();
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return;
    _shake.forward(from: 0);
  }

  void _setUnit(UnitSystem u) {
    if (u == _unit) return;
    final w = parseNumber(_weightCtrl.text);
    final h = _readHeight();
    final kg = w == null ? null : _unit.weightToKg(w);
    final cm = h == null ? null : _unit.heightToCm(h);
    setState(() {
      _unit = u;
      _weightCtrl.text = kg == null ? '' : formatNumber(u.kgToWeight(kg));
      _heightCtrl.text = cm == null
          ? ''
          : (u == UnitSystem.imperial
              ? formatImperialHeight(cm)
              : formatNumber(u.cmToHeight(cm)));
      _recompute(animate: false);
    });
  }

  Future<void> _lockIn() async {
    final after = _after;
    final kg = _kg;
    final cm = _cm;
    if (after == null || kg == null || cm == null || _saving || _locked) return;

    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      // Optimistic inside lockIn(): all avatars swap the moment this runs.
      final result = await _svc.lockIn(heightCm: cm, weightKg: kg);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _locked = true;
      });
      if (result.improved) {
        _celebrate();
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
      }
      Navigator.of(context).pop(result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Could not save. Check your connection and try again.';
      });
    }
  }

  // ───────────────────────── build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        // Subtle decaying side-to-side shake of the whole dialog.
        final t = _shake.value;
        final dx = math.sin(t * math.pi * 9) * (1 - t) * 8;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Block(
            color: Rb.slate,
            edge: Colors.black,
            radius: 22,
            depth: 8,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  const SizedBox(height: 4),
                  const BlockText(
                    'Update your stats. Your hero evolves with you!',
                    size: 11,
                    stroke: 3,
                    color: _kMuted,
                  ),
                  const SizedBox(height: 12),
                  _unitToggle(),
                  const SizedBox(height: 10),
                  _fields(),
                  const SizedBox(height: 8),
                  _compareWindow(),
                  const SizedBox(height: 6),
                  _banner(),
                  const SizedBox(height: 12),
                  _lockButton(),
                  if (_saveError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: BlockText(
                        '⚠ $_saveError',
                        size: 11,
                        stroke: 3,
                        color: const Color(0xFFFF8A80),
                        align: TextAlign.center,
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

  Widget _header() {
    return Row(
      children: [
        const Expanded(
          child: BlockText('⚖️ EVOLUTION CHECK-IN', size: 20, stroke: 4.5),
        ),
        PressBlock(
          color: Rb.red,
          edge: Rb.redEdge,
          depth: 4,
          radius: 10,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          onTap: () => Navigator.of(context).maybePop(),
          child: const BlockText('✖', size: 14, stroke: 3),
        ),
      ],
    );
  }

  Widget _unitToggle() {
    Widget tab(UnitSystem u) {
      final active = _unit == u;
      return Expanded(
        child: PressBlock(
          color: active ? Rb.blue : Rb.panel,
          edge: active ? Rb.blueEdge : Rb.panelEdge,
          depth: 5,
          radius: 12,
          forcePressed: active, // the active unit sits pressed down
          padding: const EdgeInsets.symmetric(vertical: 8),
          onTap: () => _setUnit(u),
          child: Center(
            child: BlockText(
              u.label,
              size: 12,
              stroke: 3.5,
              color: active ? Colors.white : _kMuted,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab(UnitSystem.metric),
        const SizedBox(width: 10),
        tab(UnitSystem.imperial),
      ],
    );
  }

  Widget _fields() {
    final imperial = _unit == UnitSystem.imperial;
    final digits = FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _WhiteField(
            label: '⚖️ WEIGHT',
            hint: _unit == UnitSystem.metric ? '70' : '154',
            unitTag: _unit.weightUnit,
            controller: _weightCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            formatters: [digits, LengthLimitingTextInputFormatter(6)],
            action: TextInputAction.next,
            error: _weightError,
            onChanged: (_) => setState(_recompute),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _WhiteField(
            label: '📏 HEIGHT',
            hint: imperial ? "5'8" : '172',
            unitTag: _unit.heightUnit,
            controller: _heightCtrl,
            keyboardType: imperial
                ? TextInputType.text
                : const TextInputType.numberWithOptions(decimal: true),
            formatters: [
              if (imperial)
                FilteringTextInputFormatter.allow(RegExp(r'''[0-9.'"\s\-]'''))
              else
                digits,
              LengthLimitingTextInputFormatter(7),
            ],
            action: TextInputAction.done,
            error: _heightError,
            onChanged: (_) => setState(_recompute),
          ),
        ),
      ],
    );
  }

  /// Absolute-positioned comparison window: BEFORE (left) | AFTER (right)
  /// with an arrow badge overlapping the seam.
  Widget _compareWindow() {
    const h = 214.0;
    const gap = 14.0;
    return SizedBox(
      height: h + 6,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final bw = (w - gap) / 2;
          final improved = _after != null && _after!.improvesOn(_before);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                width: bw,
                height: h,
                child: _EvoCard(
                  tag: 'BEFORE',
                  state: _before,
                  data: _data,
                  bmi: _beforeBmi,
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                width: bw,
                height: h,
                child: _EvoCard(
                  tag: 'AFTER',
                  state: _after,
                  data: _data,
                  bmi: _bmi,
                  highlight: improved,
                ),
              ),
              Positioned(
                left: w / 2 - 19,
                top: h / 2 - 19,
                width: 38,
                height: 38,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: improved ? Rb.gold : Rb.panel,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 3),
                    boxShadow: const [
                      BoxShadow(color: Colors.black, offset: Offset(0, 3)),
                    ],
                  ),
                  child: const Center(
                    child: BlockText('➜', size: 16, stroke: 3),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _banner() {
    final after = _after;
    Widget child;
    if (after == null) {
      child = const BlockText(
        'Enter your weight & height to preview your evolution',
        key: ValueKey('empty'),
        size: 11,
        stroke: 3,
        color: _kMuted,
        align: TextAlign.center,
      );
    } else if (after.improvesOn(_before)) {
      final award = _svc.wouldAwardEndurance(after);
      child = Block(
        key: const ValueKey('victory'),
        color: Rb.gold,
        edge: Rb.goldEdge,
        radius: 14,
        depth: 5,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: BlockText(
                award
                    ? 'CRITICAL PROGRESS! Your avatar has evolved into a new '
                        'form! +${EvolutionState.enduranceBonus} Endurance!'
                    : 'CRITICAL PROGRESS! Your avatar has evolved into a new '
                        'form!',
                size: 14,
                stroke: 4,
                align: TextAlign.center,
              ),
            ),
            if (!award)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: BlockText(
                  'Endurance bonus already claimed for this form',
                  size: 9,
                  stroke: 2.5,
                  align: TextAlign.center,
                ),
              ),
          ],
        ),
      );
    } else if (after != _before) {
      child = BlockText(
        'FORM CHANGED: ${_before.label.toUpperCase()} ➜ '
        '${after.label.toUpperCase()}',
        key: const ValueKey('changed'),
        size: 12,
        stroke: 3.5,
        align: TextAlign.center,
      );
    } else {
      child = BlockText(
        'Same form: ${after.label}. Keep stacking steps!',
        key: const ValueKey('same'),
        size: 12,
        stroke: 3.5,
        color: _kMuted,
        align: TextAlign.center,
      );
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (c, a) => ScaleTransition(
          scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
          child: FadeTransition(opacity: a, child: c),
        ),
        child: SizedBox(
          key: ValueKey(child.key),
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  Widget _lockButton() {
    final enabled = _after != null && !_saving && !_locked;
    final Widget label;
    if (_saving) {
      label = const SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(strokeWidth: 4, color: Colors.white),
      );
    } else if (_locked) {
      label = const BlockText('✔ LOCKED IN!', size: 20, stroke: 4.5);
    } else {
      label = BlockText(
        '💾 LOCK IN CHANGES',
        size: 20,
        stroke: 4.5,
        color: enabled ? Colors.white : _kMuted,
      );
    }
    return PressBlock(
      color: enabled || _saving || _locked ? Rb.green : Rb.slot,
      edge: enabled || _saving || _locked ? Rb.greenEdge : Rb.panelEdge,
      depth: 10,
      radius: 18,
      padding: const EdgeInsets.symmetric(vertical: 16),
      onTap: enabled ? _lockIn : null,
      child: SizedBox(width: double.infinity, child: Center(child: label)),
    );
  }
}

// ───────────────────────── pieces ─────────────────────────

/// Thick WHITE input block with a 3px solid black border and a hard shadow.
class _WhiteField extends StatelessWidget {
  final String label;
  final String hint;
  final String unitTag;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final List<TextInputFormatter> formatters;
  final TextInputAction action;
  final String? error;
  final ValueChanged<String> onChanged;

  const _WhiteField({
    required this.label,
    required this.hint,
    required this.unitTag,
    required this.controller,
    required this.keyboardType,
    required this.formatters,
    required this.action,
    required this.onChanged,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: BlockText(label, size: 12, stroke: 3.5),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black, width: 3),
            boxShadow: const [
              BoxShadow(color: Colors.black, offset: Offset(0, 4)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      keyboardType: keyboardType,
                      textInputAction: action,
                      inputFormatters: formatters,
                      onChanged: onChanged,
                      cursorColor: Colors.black,
                      style: const TextStyle(
                        color: Color(0xFF1B1D20),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: const TextStyle(
                          color: Color(0xFFB4B9C0),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 15,
                          horizontal: 12,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE3E6EA),
                      border: Border(
                        left: BorderSide(color: Colors.black, width: 3),
                      ),
                    ),
                    child: Text(
                      unitTag.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF1B1D20),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 8),
            child: BlockText(
              '⚠ $error',
              size: 10,
              stroke: 3,
              color: const Color(0xFFFF8A80),
            ),
          ),
      ],
    );
  }
}

/// One side of the comparison window: sky + grass block with the hero's
/// body sprite absolutely positioned inside.
class _EvoCard extends StatelessWidget {
  final String tag;
  final BodyCompositionState? state; // null = nothing valid typed yet
  final Map<String, dynamic> data;
  final double? bmi;
  final bool highlight;

  const _EvoCard({
    required this.tag,
    required this.state,
    required this.data,
    required this.bmi,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = CharacterProfile.fromFirestore(data);
    final raw = data['equipped_clothes'];
    final clothes =
        raw is List ? raw.whereType<String>().toList() : kDefaultClothes;
    final s = state;

    final edge = highlight ? Rb.gold : Colors.black;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _kSky,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: edge, width: 3),
        boxShadow: [
          BoxShadow(
            color: highlight ? Rb.goldEdge : Colors.black,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          children: [
            // grass baseplate
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 34,
              child: ColoredBox(color: _kGrass),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 34,
              height: 3,
              child: ColoredBox(color: Colors.black),
            ),
            // the hero body (room above for tall hair)
            Positioned(
              left: 0,
              right: 0,
              bottom: 22,
              height: 150,
              child: Center(
                child: s == null
                    ? const BlockText('?', size: 56, stroke: 6)
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (c, a) => ScaleTransition(
                          scale: Tween<double>(begin: 0.9, end: 1).animate(a),
                          child: FadeTransition(opacity: a, child: c),
                        ),
                        child: HeroSprite(
                          key: ValueKey(s),
                          bodyType: s.tier,
                          skinTone: p.skinTone,
                          hairStyle: p.hairStyle,
                          hairColor: p.hairColor,
                          face: p.faceExpression,
                          equippedClothes: clothes,
                          height: 150,
                          gender: p.gender,
                        ),
                      ),
              ),
            ),
            // tag chip (top-left)
            Positioned(
              top: 6,
              left: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: highlight ? Rb.gold : Rb.panel,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black, width: 2.5),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: BlockText(tag, size: 9, stroke: 2.5),
                ),
              ),
            ),
            // BMI chip (top-right)
            if (bmi != null)
              Positioned(
                top: 8,
                right: 6,
                child: BlockText(
                  'BMI ${bmi!.toStringAsFixed(1)}',
                  size: 9,
                  stroke: 2.5,
                ),
              ),
            // form label on the grass
            Positioned(
              left: 4,
              right: 4,
              bottom: 5,
              child: BlockText(
                s == null ? 'ENTER STATS' : '${s.emoji} ${s.label.toUpperCase()}',
                size: 11,
                stroke: 3.5,
                align: TextAlign.center,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
