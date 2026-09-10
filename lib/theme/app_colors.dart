import 'package:flutter/material.dart';

/// Centralized color palette — matches the Figma "Dungeon/Indigo" theme.
/// Update colors here once; every screen should reference these instead
/// of hardcoding hex values.
class AppColors {
  AppColors._();

  // ── Backgrounds ────────────────────────────────────────────────
  static const Color bgDeep   = Color(0xFF0A0A1F); // app background
  static const Color bgPanel  = Color(0xFF12122A); // section panels
  static const Color bgCard   = Color(0xFF181832); // individual cards/tiles

  // ── Accents ────────────────────────────────────────────────────
  static const Color blue     = Color(0xFF2F9BFF); // primary CTA, stat highlight
  static const Color cyan     = Color(0xFF00D4FF); // secondary highlight, borders
  static const Color purple   = Color(0xFF9B59FF); // CP bar, gacha, dungeon badge
  static const Color gold     = Color(0xFFFFD24C); // currency, legendary, crown
  static const Color orange   = Color(0xFFFFA542); // quest icons, walk activity
  static const Color green    = Color(0xFF2ECC71); // +XP tags, positive state
  static const Color red      = Color(0xFFFF4D5E); // HP, bronze, warnings
  static const Color silver   = Color(0xFFB9C1D9); // 2nd place / neutral accent

  // ── Text ───────────────────────────────────────────────────────
  static const Color textMain = Color(0xFFEAEAF7); // primary text
  static const Color textSub  = Color(0xFF6E6E96); // secondary/muted text

  // ── Borders / dividers ─────────────────────────────────────────
  static const Color borderDim = Color(0xFF23233F);

  // ── Rarity colors (Gacha / Gear) ───────────────────────────────
  static const Map<String, Color> rarityColor = {
    'Common'    : Color(0xFF8A8AA8),
    'Uncommon'  : Color(0xFF2ECC71),
    'Rare'      : Color(0xFF2F9BFF),
    'Epic'      : Color(0xFF9B59FF),
    'Legendary' : Color(0xFFFFD24C),
    'Divine'    : Color(0xFFFF6B6B),
  };

  // ── Gradients ──────────────────────────────────────────────────
  static const LinearGradient primaryButtonGradient = LinearGradient(
    colors: [blue, cyan],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient panelGlow = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1A1A3D), bgDeep],
  );
}