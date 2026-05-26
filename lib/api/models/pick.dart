class Pick {
  final int position;
  final String driverCode;
  const Pick({required this.position, required this.driverCode});

  factory Pick.fromJson(Map<String, dynamic> j) => Pick(
        position: j['position'] as int,
        driverCode: j['driverCode'] as String,
      );

  Map<String, dynamic> toJson() => {'position': position, 'driverCode': driverCode};
}
