class Driver {
  final String code;
  final String givenName;
  final String familyName;
  final String nationality;
  final int? permanentNumber;
  final String? image;

  const Driver({
    required this.code,
    required this.givenName,
    required this.familyName,
    required this.nationality,
    this.permanentNumber,
    this.image,
  });

  factory Driver.fromJson(Map<String, dynamic> j) => Driver(
        code: j['code'] as String,
        givenName: j['givenName'] as String,
        familyName: j['familyName'] as String,
        nationality: j['nationality'] as String,
        permanentNumber: j['permanentNumber'] as int?,
        image: j['image'] as String?,
      );
}
