import 'package:flutter/material.dart';

import 'block_ui.dart';

/// Chunky light-gray input block: 3px black border + hard 4px bottom shadow.
class BlockTextField extends StatelessWidget {
  final String label;
  final String hint;
  final String icon; // emoji
  final TextEditingController controller;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final String? error;
  final TextInputAction? action;
  final ValueChanged<String>? onSubmitted;

  const BlockTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.onChanged,
    this.error,
    this.action,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final bad = error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: BlockText(label, size: 12, stroke: 3.5),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF2F3F5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: bad ? Rb.red : Colors.black, width: 3),
            boxShadow: [
              BoxShadow(
                color: bad ? Rb.redEdge : Colors.black,
                offset: const Offset(0, 4),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(icon, style: const TextStyle(fontSize: 20)),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  keyboardType: keyboardType,
                  textInputAction: action,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  cursorColor: Colors.black,
                  style: const TextStyle(
                    color: Color(0xFF1B1D20),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(
                      color: Color(0xFF8A8F96),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  ),
                ),
              ),
              if (suffix != null) suffix!,
            ],
          ),
        ),
        if (bad)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 8),
            child: BlockText('⚠ $error', size: 11, stroke: 3, color: const Color(0xFFFF8A80)),
          ),
      ],
    );
  }
}

/// Massive neon-blue 3D CTA that sinks when pressed.
class NeonBlueButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onTap;

  const NeonBlueButton({
    super.key,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return PressBlock(
      color: Rb.blue,
      edge: Rb.blueEdge,
      depth: 10,
      radius: 18,
      padding: const EdgeInsets.symmetric(vertical: 20),
      onTap: loading ? null : onTap,
      child: SizedBox(
        width: double.infinity,
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 4, color: Colors.white),
                )
              : BlockText(label, size: 24, stroke: 5),
        ),
      ),
    );
  }
}

void blockSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Rb.panel,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.black, width: 3),
        ),
        content: BlockText(msg, size: 12, stroke: 3),
      ),
    );
}

/// Sky-blue title banner shared by Login / Sign Up.
class AuthBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  const AuthBanner({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Block(
      color: const Color(0xFF8FD0FF),
      edge: Rb.blueEdge,
      depth: 8,
      radius: 22,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 150,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(19),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const BlockBackground(id: 'valley'),
              Container(color: Colors.black.withValues(alpha: 0.15)),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🏃‍♂️', style: TextStyle(fontSize: 36)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: BlockText(title, size: 28, stroke: 6),
                    ),
                    const SizedBox(height: 2),
                    BlockText(subtitle, size: 11, stroke: 3, color: Rb.gold),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
