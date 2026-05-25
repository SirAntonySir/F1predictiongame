class SessionResult {
  final int position;
  final String driverCode;
  final String driverName;
  final String constructorId;
  final String constructorName;
  final String? raceTime;
  final String? status;
  final int? points;
  final String? fastestLap;
  final String? fastestLapTime;
  final String? fastestLapSpeed;
  final String? q1;
  final String? q2;
  final String? q3;

  const SessionResult({
    required this.position,
    required this.driverCode,
    required this.driverName,
    required this.constructorId,
    required this.constructorName,
    this.raceTime,
    this.status,
    this.points,
    this.fastestLap,
    this.fastestLapTime,
    this.fastestLapSpeed,
    this.q1,
    this.q2,
    this.q3,
  });

  factory SessionResult.fromJson(Map<String, dynamic> j) => SessionResult(
        position: j['position'] as int,
        driverCode: j['driverCode'] as String,
        driverName: j['driverName'] as String,
        constructorId: j['constructorId'] as String,
        constructorName: j['constructorName'] as String,
        raceTime: j['raceTime'] as String?,
        status: j['status'] as String?,
        points: j['points'] as int?,
        fastestLap: j['fastestLap'] as String?,
        fastestLapTime: j['fastestLapTime'] as String?,
        fastestLapSpeed: j['fastestLapSpeed'] as String?,
        q1: j['q1'] as String?,
        q2: j['q2'] as String?,
        q3: j['q3'] as String?,
      );
}
