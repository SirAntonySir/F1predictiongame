import 'package:flutter/material.dart';
class StandingsScreen extends StatelessWidget {
  final String subTab;
  const StandingsScreen({super.key, this.subTab = 'league'});
  @override Widget build(BuildContext context) => Scaffold(body: Center(child: Text('Standings: $subTab')));
}
