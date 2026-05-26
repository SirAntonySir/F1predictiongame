import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('session results screen no longer contains a PICK VS RESULT heading', () {
    final src = File('lib/screens/session_results_screen.dart').readAsStringSync();
    expect(src.contains('PICK VS RESULT'), isFalse,
        reason: 'PICK VS RESULT was intentionally removed; FULL CLASSIFICATION shows the same info inline.');
  });
}
