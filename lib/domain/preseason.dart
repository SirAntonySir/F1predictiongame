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

const int preseasonMaxPoints = 148;
