import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/components/fact_card.dart';
import 'package:predictiongame/components/league_row.dart';
import 'package:predictiongame/components/score_banner.dart';
import 'package:predictiongame/components/trajectory_chart.dart';
import 'package:predictiongame/components/trend_badge.dart';
import 'package:predictiongame/theme/app_theme.dart';

Widget _frame(Widget c) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SizedBox(width: 360, child: c)),
    );

void main() {
  testWidgets('LeagueRow shows rank, name, points', (tester) async {
    await tester.pumpWidget(_frame(const LeagueRow(
      rank: 3, initials: 'AN', name: 'Anton', subtitle: '+24 last race',
      points: 148, trend: TrendDirection.equal, isMe: true,
    )));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Anton'), findsOneWidget);
    expect(find.text('148'), findsOneWidget);
  });

  testWidgets('ScoreBanner shows label + big number', (tester) async {
    await tester.pumpWidget(_frame(const ScoreBanner(
      label: 'Your score', value: '+24', subtitle: '3 exact', trailing: '2nd in The Box',
    )));
    expect(find.text('+24'), findsOneWidget);
    expect(find.text('Your score'), findsOneWidget);
  });

  testWidgets('FactCard shows emblem + text', (tester) async {
    await tester.pumpWidget(_frame(const FactCard(emblem: '★', text: 'Lukas won 4')));
    expect(find.text('★'), findsOneWidget);
    expect(find.text('Lukas won 4'), findsOneWidget);
  });

  testWidgets('TrajectoryChart paints without throwing', (tester) async {
    await tester.pumpWidget(_frame(const TrajectoryChart(
      series: [
        ChartSeries(label: 'You', color: Colors.red, points: [0, 18, 40, 56, 72, 90, 114, 148]),
        ChartSeries(label: 'Leader', color: Colors.black, points: [0, 25, 50, 75, 100, 125, 150, 167]),
      ],
      xLabels: ['R1','R2','R3','R4','R5','R6','R7','R8'],
    )));
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
