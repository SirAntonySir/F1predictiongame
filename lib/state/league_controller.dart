import 'package:flutter/foundation.dart';
import '../domain/league.dart';

const League theBoxLeague = League(
  id: 'the_box',
  name: 'The Box',
  players: [
    Player(id: 'anton', displayName: 'Anton'),
    Player(id: 'lukas', displayName: 'Lukas'),
    Player(id: 'simon', displayName: 'Simon'),
    Player(id: 'paul', displayName: 'Paul'),
    Player(id: 'peter', displayName: 'Peter'),
  ],
);

class LeagueController extends ChangeNotifier {
  final League _league;
  LeagueController({required League league}) : _league = league;
  League get league => _league;
}
