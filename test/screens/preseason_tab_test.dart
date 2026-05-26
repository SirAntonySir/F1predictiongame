import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/league_preseason_view.dart';
import 'package:predictiongame/domain/preseason.dart';
import 'package:predictiongame/screens/standings/preseason_tab.dart';
import 'package:predictiongame/theme/app_theme.dart';

Widget _frame(Widget c) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: c),
    );

void main() {
  testWidgets('PreseasonTab renders 6 category cards + standings + leaderboard', (tester) async {
    final view = LeaguePreseasonView(
      seasonYear: 2026,
      isLocked: false,
      me: MyPreseasonView(
        categories: [
          for (final cat in PreseasonCategory.values)
            CategoryProjectionView(
              category: cat,
              myPick: const PickPairView(driverCode: 'VER', constructorId: 'red_bull'),
              projectedTruth:
                  cat == PreseasonCategory.surprise || cat == PreseasonCategory.disappointment
                      ? null
                      : const PickPairView(driverCode: 'VER', constructorId: 'red_bull'),
              projectedPoints:
                  cat == PreseasonCategory.surprise || cat == PreseasonCategory.disappointment
                      ? 0
                      : 8,
              max: 8,
            ),
        ],
        standings: const StandingsProjectionView(
          myDriverPicks: [StandingsDriverPickView(position: 1, driverCode: 'VER')],
          myConstructorPicks: [StandingsConstructorPickView(position: 1, constructorId: 'red_bull')],
          projectedDriverOrder: ['VER'],
          projectedConstructorOrder: ['red_bull'],
          projectedPoints: 7,
          max: 60,
        ),
        projectedPointsTotal: 47,
      ),
      leaderboard: const [
        LeaguePreseasonLeaderboardRow(userId: 'u1', displayName: 'Me', preseasonPointsProjected: 47),
        LeaguePreseasonLeaderboardRow(userId: 'u2', displayName: 'Other', preseasonPointsProjected: 16),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(400, 2000));
    await tester.pumpWidget(_frame(PreseasonTab.withView(view, myUserId: 'u1')));
    await tester.pumpAndSettle();
    expect(find.text('SURPRISE'), findsOneWidget);
    expect(find.text('DISAPPOINTMENT'), findsOneWidget);
    expect(find.text('Set at season end'), findsNWidgets(2));
    expect(find.text('Me'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
  });
}
