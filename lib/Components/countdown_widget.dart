import 'package:flutter/material.dart';

class CountdownWidget extends StatelessWidget {
  final Duration? timeUntilNextRace;
  final bool raceStarted;

  CountdownWidget({required this.timeUntilNextRace, required this.raceStarted});

  String twoDigits(int n) => n.toString().padLeft(2, "0");

  Widget buildTimeBox(String value, String label) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
        SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (timeUntilNextRace == null || raceStarted) return SizedBox.shrink();

    String days = timeUntilNextRace!.inDays.toString();
    String hours = twoDigits(timeUntilNextRace!.inHours.remainder(24));
    String minutes = twoDigits(timeUntilNextRace!.inMinutes.remainder(60));
    String seconds = twoDigits(timeUntilNextRace!.inSeconds.remainder(60));

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        buildTimeBox(days, "DAYS"),
        SizedBox(width: 12),
        buildTimeBox(hours, "HOURS"),
        SizedBox(width: 12),
        buildTimeBox(minutes, "MINUTES"),
        SizedBox(width: 12),
        buildTimeBox(seconds, "SECONDS"),
      ],
    );
  }
}
