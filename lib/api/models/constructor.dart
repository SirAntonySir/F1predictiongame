class Constructor {
  final String id;
  final String name;
  final String nationality;
  final String? image;

  const Constructor({
    required this.id,
    required this.name,
    required this.nationality,
    this.image,
  });

  factory Constructor.fromJson(Map<String, dynamic> j) => Constructor(
        id: j['id'] as String,
        name: j['name'] as String,
        nationality: j['nationality'] as String,
        image: j['image'] as String?,
      );
}
