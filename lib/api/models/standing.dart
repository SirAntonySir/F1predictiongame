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

  factory DriverStanding.fromJson(Map<String, dynamic> j) => DriverStanding(
        position: j['position'] as int,
        driverCode: j['driverCode'] as String,
        driverName: j['driverName'] as String,
        constructorId: j['constructorId'] as String,
        points: j['points'] as int,
        wins: j['wins'] as int,
        image: j['image'] as String?,
      );
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

  factory ConstructorStanding.fromJson(Map<String, dynamic> j) =>
      ConstructorStanding(
        position: j['position'] as int,
        constructorId: j['constructorId'] as String,
        constructorName: j['constructorName'] as String,
        points: j['points'] as int,
        wins: j['wins'] as int,
        image: j['image'] as String?,
      );
}
