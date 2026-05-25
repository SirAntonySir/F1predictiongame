class Season {
  final int year;
  final bool isCurrent;
  const Season({required this.year, required this.isCurrent});
  factory Season.fromJson(Map<String, dynamic> j) =>
      Season(year: j['year'] as int, isCurrent: j['isCurrent'] as bool);
}
