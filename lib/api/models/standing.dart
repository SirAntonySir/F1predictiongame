class DriverStanding {
  final int position;
  final String driverCode;
  final String driverName;
  final String constructorId;
  final int points;
  final int wins;
  final String? image;

  const DriverStanding({
    required this.position,
    required this.driverCode,
    required this.driverName,
    required this.constructorId,
    required this.points,
    required this.wins,
    this.image,
  });

  factory DriverStanding.fromJson(Map<String, dynamic> j) {
    final nested = j['driver'] is Map<String, dynamic>
        ? j['driver'] as Map<String, dynamic>
        : null;
    final name = (j['driverName'] as String?) ??
        (nested == null
            ? ''
            : '${nested['givenName'] ?? ''} ${nested['familyName'] ?? ''}'.trim());
    return DriverStanding(
      position: j['position'] as int,
      driverCode: j['driverCode'] as String,
      driverName: name,
      constructorId: j['constructorId'] as String,
      points: j['points'] as int,
      wins: j['wins'] as int,
      image: (j['image'] as String?) ?? (nested?['image'] as String?),
    );
  }
}

class ConstructorStanding {
  final int position;
  final String constructorId;
  final String constructorName;
  final int points;
  final int wins;
  final String? image;

  const ConstructorStanding({
    required this.position,
    required this.constructorId,
    required this.constructorName,
    required this.points,
    required this.wins,
    this.image,
  });

  factory ConstructorStanding.fromJson(Map<String, dynamic> j) {
    final nested = j['constructor'] is Map<String, dynamic>
        ? j['constructor'] as Map<String, dynamic>
        : null;
    final name = (j['constructorName'] as String?) ??
        (nested?['name'] as String?) ??
        (j['constructorId'] as String);
    return ConstructorStanding(
      position: j['position'] as int,
      constructorId: j['constructorId'] as String,
      constructorName: name,
      points: j['points'] as int,
      wins: j['wins'] as int,
      image: (j['image'] as String?) ?? (nested?['image'] as String?),
    );
  }
}
