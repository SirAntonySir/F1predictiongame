const Map<String, String> _flags = {
  'bahrain': '🇧🇭',
  'saudi arabia': '🇸🇦',
  'australia': '🇦🇺',
  'japan': '🇯🇵',
  'china': '🇨🇳',
  'usa': '🇺🇸',
  'united states': '🇺🇸',
  'italy': '🇮🇹',
  'monaco': '🇲🇨',
  'canada': '🇨🇦',
  'spain': '🇪🇸',
  'austria': '🇦🇹',
  'uk': '🇬🇧',
  'united kingdom': '🇬🇧',
  'great britain': '🇬🇧',
  'hungary': '🇭🇺',
  'belgium': '🇧🇪',
  'netherlands': '🇳🇱',
  'singapore': '🇸🇬',
  'mexico': '🇲🇽',
  'brazil': '🇧🇷',
  'qatar': '🇶🇦',
  'uae': '🇦🇪',
  'united arab emirates': '🇦🇪',
  'azerbaijan': '🇦🇿',
  'france': '🇫🇷',
  'germany': '🇩🇪',
  'portugal': '🇵🇹',
  'turkey': '🇹🇷',
  'russia': '🇷🇺',
  'south korea': '🇰🇷',
};

String? flagFor(String country) => _flags[country.toLowerCase()];

/// Two-letter ISO 3166-1 alpha-2 country code for [country], derived from
/// the corresponding flag emoji's regional-indicator codepoints (🇫🇷 → "FR").
/// Used by the `country_flags` package's SVG renderer when the emoji isn't
/// big or shape-controlled enough — e.g. when a flag needs to fill a chip
/// or a tile thumbnail.
String? isoCodeFor(String country) {
  final emoji = flagFor(country);
  if (emoji == null || emoji.isEmpty) return null;
  final runes = emoji.runes.toList();
  if (runes.length < 2) return null;
  const base = 0x1F1E6; // regional indicator A
  final a = runes[0] - base;
  final b = runes[1] - base;
  if (a < 0 || a > 25 || b < 0 || b > 25) return null;
  return String.fromCharCodes([65 + a, 65 + b]);
}
