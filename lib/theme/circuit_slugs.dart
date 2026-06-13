/// Maps a backend Event to the corresponding circuit id used by
/// julesr0y/f1-circuits-svg (and our /api/circuits endpoint).
///
/// We prefer matching by `circuitName` first (most reliable — F1 has multiple
/// GPs in one country running on different circuits, e.g. Spain 2026 hosts
/// Catalunya for the Barcelona GP and Madring for the Spanish GP). Falls back
/// to country / name matching when the circuit name doesn't match a known
/// substring. Returns null when no match — the SVG widget then renders nothing.
String? circuitIdForEvent({
  required String name,
  required String country,
  String? circuitName,
}) {
  final cn = (circuitName ?? '').toLowerCase();
  // Direct substring match on the circuit name. Beats country/name guesses
  // whenever upstream has a recognisable name in the field. Ordering matters
  // — match longer / more specific tokens first so e.g. "spa-francorchamps"
  // doesn't accidentally trip another rule.
  for (final entry in _byCircuitNamePart.entries) {
    if (cn.contains(entry.key)) return entry.value;
  }

  final c = country.toLowerCase().trim();
  final n = name.toLowerCase();
  // Country-disambiguated fallbacks for events where the circuitName lookup
  // missed (e.g. Jolpica returns just the country, no useful circuit string).
  if (c == 'spain' || c == 'es' || c == 'esp') {
    if (n.contains('madrid')) return 'madring';
    return 'catalunya';
  }
  if (c == 'italy' || c == 'ita') {
    if (n.contains('emilia') || n.contains('imola')) return 'imola';
    return 'monza';
  }
  if (c == 'usa' || c == 'united states' || c == 'us') {
    if (n.contains('miami')) return 'miami';
    if (n.contains('las vegas')) return 'las-vegas';
    return 'austin';
  }
  return _byCountry[c];
}

// circuit_name substring → circuit id. Substrings are lowercased and
// generally specific enough to avoid false positives (e.g. "madring" only
// ever refers to the Madrid circuit). Ordered most-specific-first so a
// circuit name containing several tokens picks the right one.
const _byCircuitNamePart = <String, String>{
  'madring': 'madring',
  'catalunya': 'catalunya',
  'barcelona': 'catalunya',
  'imola': 'imola',
  'monza': 'monza',
  'monaco': 'monaco',
  'silverstone': 'silverstone',
  'spa-francorchamps': 'spa-francorchamps',
  'spa francorchamps': 'spa-francorchamps',
  'hungaroring': 'hungaroring',
  'suzuka': 'suzuka',
  'zandvoort': 'zandvoort',
  'red bull ring': 'spielberg',
  'spielberg': 'spielberg',
  'gilles villeneuve': 'montreal',
  'montreal': 'montreal',
  'mexico': 'mexico-city',
  'autódromo hermanos rodríguez': 'mexico-city',
  'interlagos': 'interlagos',
  'josé carlos pace': 'interlagos',
  'jose carlos pace': 'interlagos',
  'marina bay': 'marina-bay',
  'baku': 'baku',
  'yas marina': 'yas-marina',
  'jeddah': 'jeddah',
  'lusail': 'lusail',
  'las vegas': 'las-vegas',
  'miami': 'miami',
  'circuit of the americas': 'austin',
  'cota': 'austin',
  'austin': 'austin',
  'shanghai': 'shanghai',
  'albert park': 'melbourne',
  'melbourne': 'melbourne',
  'bahrain': 'bahrain',
};

const _byCountry = <String, String>{
  'australia': 'melbourne',
  'aus': 'melbourne',
  'austria': 'spielberg',
  'aut': 'spielberg',
  'azerbaijan': 'baku',
  'aze': 'baku',
  'bahrain': 'bahrain',
  'bhr': 'bahrain',
  'belgium': 'spa-francorchamps',
  'bel': 'spa-francorchamps',
  'brazil': 'interlagos',
  'bra': 'interlagos',
  'canada': 'montreal',
  'can': 'montreal',
  'china': 'shanghai',
  'chn': 'shanghai',
  'france': 'le-castellet',  // not on the 2024+ calendar; kept for completeness
  'fra': 'le-castellet',
  'germany': 'hockenheim',
  'ger': 'hockenheim',
  'hungary': 'hungaroring',
  'hun': 'hungaroring',
  'japan': 'suzuka',
  'jpn': 'suzuka',
  'mexico': 'mexico-city',
  'mex': 'mexico-city',
  'monaco': 'monaco',
  'mco': 'monaco',
  'netherlands': 'zandvoort',
  'ned': 'zandvoort',
  'qatar': 'lusail',
  'qat': 'lusail',
  'saudi arabia': 'jeddah',
  'sau': 'jeddah',
  'singapore': 'marina-bay',
  'sgp': 'marina-bay',
  'united kingdom': 'silverstone',
  'gbr': 'silverstone',
  'uk': 'silverstone',
  'united arab emirates': 'yas-marina',
  'uae': 'yas-marina',
};
