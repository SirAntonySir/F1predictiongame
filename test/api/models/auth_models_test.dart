import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/auth_result.dart';
import 'package:predictiongame/api/models/league_member.dart';
import 'package:predictiongame/api/models/league_view.dart';
import 'package:predictiongame/api/models/me_result.dart';
import 'package:predictiongame/api/models/user.dart';
import 'package:predictiongame/api/models/user_league.dart';

void main() {
  test('User.fromJson', () {
    final u = User.fromJson({
      'id': 'u1', 'email': 'a@b.com', 'displayName': 'A', 'createdAt': '2026-05-01T00:00:00.000Z',
    });
    expect(u.id, 'u1');
    expect(u.displayName, 'A');
    expect(u.createdAt.toIso8601String(), '2026-05-01T00:00:00.000Z');
  });

  test('UserLeague.fromJson', () {
    final l = UserLeague.fromJson({'id': 'L', 'name': 'My League', 'role': 'owner'});
    expect(l.role, 'owner');
  });

  test('LeagueMember.fromJson', () {
    final m = LeagueMember.fromJson({'userId': 'u2', 'displayName': 'B', 'role': 'member'});
    expect(m.id, 'u2');
    expect(m.displayName, 'B');
  });

  test('LeagueView.fromJson with optional joinCode', () {
    final l = LeagueView.fromJson({
      'league': {'id': 'L', 'name': 'My League', 'role': 'owner', 'joinCode': 'ABC123'},
      'members': [
        {'userId': 'u1', 'displayName': 'A', 'role': 'owner'},
        {'userId': 'u2', 'displayName': 'B', 'role': 'member'},
      ]
    });
    expect(l.id, 'L');
    expect(l.role, 'owner');
    expect(l.joinCode, 'ABC123');
    expect(l.members.length, 2);

    final asMember = LeagueView.fromJson({
      'league': {'id': 'L', 'name': 'My League', 'role': 'member'},
      'members': []
    });
    expect(asMember.joinCode, isNull);
  });

  test('AuthResult.fromJson', () {
    final r = AuthResult.fromJson({
      'user': {'id': 'u1', 'email': 'a@b.com', 'displayName': 'A', 'createdAt': '2026-05-01T00:00:00.000Z'},
      'token': 'tok',
    });
    expect(r.token, 'tok');
    expect(r.user.id, 'u1');
  });

  test('MeResult.fromJson', () {
    final r = MeResult.fromJson({
      'user': {'id': 'u1', 'email': 'a@b.com', 'displayName': 'A', 'createdAt': '2026-05-01T00:00:00.000Z'},
      'leagues': [
        {'id': 'L1', 'name': 'Eins', 'role': 'owner'},
        {'id': 'L2', 'name': 'Zwei', 'role': 'member'},
      ]
    });
    expect(r.leagues.length, 2);
    expect(r.leagues[1].role, 'member');
  });
}
