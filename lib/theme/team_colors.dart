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
};

const Map<String, String> _aliases = {
  'alphatauri': 'rb',
  'alpha_tauri': 'rb',
  'alfa': 'kick_sauber',
  'alfa_romeo': 'kick_sauber',
  'sauber': 'kick_sauber',
};

const Color _fallback = Color(0xFF707070);

Color teamColor(String constructorId) {
  final id = _aliases[constructorId] ?? constructorId;
  return _teamColors[id] ?? _fallback;
}
