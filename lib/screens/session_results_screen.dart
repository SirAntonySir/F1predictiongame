import 'package:flutter/material.dart';
class SessionResultsScreen extends StatelessWidget {
  final int round;
  final int sessionId;
  const SessionResultsScreen({super.key, required this.round, required this.sessionId});
  @override Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('Race $round / Session $sessionId')));
}
