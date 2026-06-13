import 'package:flutter/material.dart';

const Map<String, Color> _teamColors = {
  'red_bull': Color(0xFF1E41FF),
  'ferrari': Color(0xFFE8002D),
  'mclaren': Color(0xFFFF8000),
  'mercedes': Color(0xFF27F4D2),
  'aston_martin': Color(0xFF229971),
  'alpine': Color(0xFF0093CC),
  'kick_sauber': Color(0xFF52E252),
  'rb': Color(0xFF6692FF),
  'haas': Color(0xFFB6BABD),
  'williams': Color(0xFF64C4FF),
  // New for 2026. Audi uses its OpenF1 brand red; Cadillac gets a brand navy
  // because OpenF1 currently publishes a placeholder grey (909090) that would
  // be indistinguishable from the neutral fallback.
  'audi': Color(0xFFF50537),
  'cadillac': Color(0xFF1A2B4A),
};

const Map<String, String> _aliases = {
  'alphatauri': 'rb',
  'alpha_tauri': 'rb',
  'alfa': 'kick_sauber',
  'alfa_romeo': 'kick_sauber',
  'sauber': 'kick_sauber',
  // The session-results data source uses OpenF1-style team ids, which differ
  // from the (Ergast-style) ids above. Without these aliases the predict
  // screen's driver grid falls back to grey for these teams.
  'red_bull_racing': 'red_bull',
  'haas_f1_team': 'haas',
  'racing_bulls': 'rb',
};

const Color _fallback = Color(0xFF707070);

/// Curated map first; if missing and a fallback hex is provided
/// (e.g. from the backend's OpenF1 `teamColour` field), use it; else neutral grey.
Color teamColor(String constructorId, {String? fallbackHex}) {
  final id = _aliases[constructorId] ?? constructorId;
  final curated = _teamColors[id];
  if (curated != null) return curated;
  if (fallbackHex != null && RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(fallbackHex)) {
    return Color(int.parse(fallbackHex, radix: 16) | 0xFF000000);
  }
  return _fallback;
}
