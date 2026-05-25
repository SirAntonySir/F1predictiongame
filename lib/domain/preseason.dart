// ignore_for_file: constant_identifier_names
enum PreseasonCategory {
  surprise,
  disappointment,
  dnf,
  poles,
  fastest_lap,
  wdc_wcc,
}

class PreseasonCategoryMeta {
  final String title;
  final String subtitle;
  final String emblem;
  final int max;
  const PreseasonCategoryMeta({
    required this.title,
    required this.subtitle,
    required this.emblem,
    required this.max,
  });
}

const Map<PreseasonCategory, PreseasonCategoryMeta> preseasonMeta = {
  PreseasonCategory.surprise: PreseasonCategoryMeta(
    title: 'Biggest surprise',
    subtitle: 'The driver and team that punch above their weight.',
    emblem: '!?',
    max: 8,
  ),
  PreseasonCategory.disappointment: PreseasonCategoryMeta(
    title: 'Biggest disappointment',
    subtitle: 'Who falls flat against the hype.',
    emblem: 'X',
    max: 8,
  ),
  PreseasonCategory.dnf: PreseasonCategoryMeta(
    title: 'Most DNFs',
    subtitle: 'Most retirements across race + sprint sessions.',
    emblem: '✕',
    max: 8,
  ),
  PreseasonCategory.poles: PreseasonCategoryMeta(
    title: 'Most poles',
    subtitle: 'Most P1 starts in qualifying.',
    emblem: 'P1',
    max: 8,
  ),
  PreseasonCategory.fastest_lap: PreseasonCategoryMeta(
    title: 'Most fastest laps',
    subtitle: 'Most fastest-lap awards across races.',
    emblem: 'FL',
    max: 8,
  ),
  PreseasonCategory.wdc_wcc: PreseasonCategoryMeta(
    title: 'WDC + WCC',
    subtitle: "Season's drivers' and constructors' champion.",
    emblem: '★',
    max: 8,
  ),
};

class PreseasonPick {
  final String? driverCode;
  final String? constructorId;
  const PreseasonPick({this.driverCode, this.constructorId});
  bool get isEmpty => driverCode == null && constructorId == null;
  Map<String, dynamic> toJson() => {
        'driverCode': driverCode,
        'constructorId': constructorId,
      };
  factory PreseasonPick.fromJson(Map<String, dynamic> j) => PreseasonPick(
        driverCode: j['driverCode'] as String?,
        constructorId: j['constructorId'] as String?,
      );
}

/// Points awarded per exact slot in the championship-ordering category.
const int preseasonPointsPerDriverSlot = 3;
const int preseasonPointsPerConstructorSlot = 4;

/// Total max points for a season given the actual driver + team field size.
///
/// 6 single-pick categories × 8 pts (max 48)
/// + N drivers × 3 + N teams × 4 (the championship ordering)
int preseasonMaxPoints({required int driverCount, required int constructorCount}) {
  final singles = PreseasonCategory.values
      .map((c) => preseasonMeta[c]!.max)
      .fold<int>(0, (a, b) => a + b);
  return singles +
      driverCount * preseasonPointsPerDriverSlot +
      constructorCount * preseasonPointsPerConstructorSlot;
}
