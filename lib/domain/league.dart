class Player {
  final String id;
  final String displayName;
  const Player({required this.id, required this.displayName});
  String get initials {
    final parts = displayName.trim().split(' ');
    final letters = parts.map((p) => p.isEmpty ? '' : p[0]).take(2).join();
    return letters.toUpperCase();
  }
}

class League {
  final String id;
  final String name;
  final List<Player> players;
  const League({required this.id, required this.name, required this.players});
}
