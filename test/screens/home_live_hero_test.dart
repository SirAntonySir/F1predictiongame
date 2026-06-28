import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/api/models/live_snapshot.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/session_result.dart';
import 'package:predictiongame/screens/home_screen.dart' show LiveHeroCard;

Event _ev() => const Event(
      round: 6,
      name: 'Monaco Grand Prix',
      country: 'Monaco',
      circuitName: 'Monte Carlo',
      hasSprint: false,
      sessions: [],
    );

Session _sess() => Session(
      id: 30,
      type: SessionType.race,
      scheduledStart: DateTime.utc(2026, 6, 7, 13),
      scheduledEnd: DateTime.utc(2026, 6, 7, 15),
      status: SessionStatus.scheduled,
    );

void main() {
  testWidgets(
      'LiveHeroCard shows LIVE·RACE, event title, top order (with names) and projected',
      (tester) async {
    const snap = LiveSnapshot(
      sessionId: 30,
      state: LiveState.live,
      order: [
        SessionResult(
            position: 1,
            driverCode: 'VER',
            driverName: 'Max Verstappen',
            constructorId: 'red_bull_racing',
            constructorName: 'Red Bull Racing',
            teamColour: '3671c6'),
        SessionResult(
            position: 2,
            driverCode: 'LEC',
            driverName: 'Charles Leclerc',
            constructorId: 'ferrari',
            constructorName: 'Ferrari'),
      ],
      myPointsTotal: 8,
      league: [],
    );
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListView(children: [
      LiveHeroCard(event: _ev(), session: _sess(), snap: snap, onTap: () {}),
    ]))));
    expect(find.text('LIVE · RACE'), findsOneWidget);
    expect(find.text('MONACO GRAND PRIX'), findsOneWidget);
    expect(find.text('VER'), findsOneWidget);
    expect(find.text('Max Verstappen'), findsOneWidget);
    expect(find.text('+8'), findsOneWidget);
  });

  testWidgets(
      'LiveHeroCard renders with a null snapshot, defaulting the badge to LIVE',
      (tester) async {
    // While the race is running by the schedule but the backend `/live`
    // snapshot hasn't arrived (or isn't reporting `live` yet), the home hero
    // still surfaces the running session — with no snapshot the card defaults
    // to the LIVE badge rather than crashing or falling back to the next event.
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListView(children: [
      LiveHeroCard(event: _ev(), session: _sess(), snap: null, onTap: () {}),
    ]))));
    expect(find.text('LIVE · RACE'), findsOneWidget);
    expect(find.text('MONACO GRAND PRIX'), findsOneWidget);
  });

  testWidgets('LiveHeroCard shows the PROVISIONAL badge', (tester) async {
    const snap = LiveSnapshot(
      sessionId: 30,
      state: LiveState.provisional,
      order: [],
      myPointsTotal: null,
      league: [],
    );
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListView(children: [
      LiveHeroCard(event: _ev(), session: _sess(), snap: snap, onTap: () {}),
    ]))));
    expect(find.text('PROVISIONAL · RACE'), findsOneWidget);
  });
}
