import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/main.dart';

void main() {
  testWidgets('App boots and shows brand placeholder', (tester) async {
    await tester.pumpWidget(const F1PgApp());
    expect(find.text('F1PG'), findsOneWidget);
  });
}
