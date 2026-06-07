import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/live_snapshot.dart';
import 'package:predictiongame/api/models/session_result.dart';
import 'package:predictiongame/screens/home_screen.dart' show LiveHeroCard;

void main() {
  testWidgets(
      'LiveHeroCard shows LIVE, event/session, top order and my projected points',
      (tester) async {
    const snap = LiveSnapshot(
      sessionId: 5,
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
            body: LiveHeroCard(
                eventName: 'Spanish GP',
                sessionLabel: 'RACE',
                snap: snap,
                onTap: () {}))));
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.textContaining('Spanish GP'), findsOneWidget);
    expect(find.text('VER'), findsOneWidget);
    expect(find.text('+8'), findsOneWidget);
  });

  testWidgets('LiveHeroCard shows PROVISIONAL badge past session end',
      (tester) async {
    const snap = LiveSnapshot(
      sessionId: 5,
      state: LiveState.provisional,
      order: [],
      myPointsTotal: null,
      league: [],
    );
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: LiveHeroCard(
                eventName: 'Spanish GP',
                sessionLabel: 'RACE',
                snap: snap,
                onTap: () {}))));
    expect(find.text('PROVISIONAL'), findsOneWidget);
  });
}
