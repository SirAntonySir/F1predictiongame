import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const F1PgApp());
}

class F1PgApp extends StatelessWidget {
  const F1PgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'F1PG',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const Scaffold(body: Center(child: Text('F1PG'))),
    );
  }
}
