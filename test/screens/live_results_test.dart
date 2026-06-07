import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/live_snapshot.dart';
import 'package:predictiongame/api/models/member_prediction.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/session_result.dart';
import 'package:predictiongame/screens/session_results_screen.dart'
    show LiveResultsBody;

void main() {
  testWidgets(
      'LiveResultsBody shows projected score, live order and league projections',
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
      league: [
        MemberPrediction(
            userId: 'u2', displayName: 'Lukas', picks: [], pointsTotal: 3)
      ],
    );
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: LiveResultsBody(
                    sessionType: SessionType.race,
                    myPicks: ['VER', 'LEC', 'X', 'Y', 'Z'],
                    snap: snap)))));
    expect(find.textContaining('projected'), findsWidgets);
    expect(find.text('+8'), findsOneWidget);
    expect(find.text('VER'), findsOneWidget);
    expect(find.text('LUKAS'), findsOneWidget);
    expect(find.textContaining('LEAGUE'), findsOneWidget);
  });
}
