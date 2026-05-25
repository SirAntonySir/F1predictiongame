import 'package:flutter/material.dart';

void main() {
  runApp(const F1PgApp());
}

class F1PgApp extends StatelessWidget {
  const F1PgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'F1PG',
      home: Scaffold(body: Center(child: Text('F1PG'))),
    );
  }
}
