import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  final Future<void> Function() onRetry;
  final Object? error;
  const SplashScreen({super.key, required this.onRetry, this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: error == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Couldn't reach the server"),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () => onRetry(), child: const Text('Retry')),
                  ],
                ),
        ),
      ),
    );
  }
}
