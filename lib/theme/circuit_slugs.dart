/// Maps a backend Event to the corresponding circuit id used by
/// julesr0y/f1-circuits-svg (and our /api/circuits endpoint).
///
/// We prefer matching by country since each country on the modern F1 grid
/// hosts exactly one circuit. When two GPs share a country (Spanish GP at
/// Catalunya vs the new Spanish GP at Madring in 2026), we fall back to the
/// event name. Returns null when no match — the SVG widget then renders
/// nothing.
String? circuitIdForEvent({required String name, required String country}) {
  final c = country.toLowerCase().trim();
  final n = name.toLowerCase();
  // Country-disambiguated cases (multiple GPs in one country).
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
  // 1-to-1 country → circuit mappings.
  return _byCountry[c];
}

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
