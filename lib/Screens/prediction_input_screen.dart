import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class PredictionInputScreen extends StatefulWidget {
  @override
  _PredictionInputScreenState createState() => _PredictionInputScreenState();
}

class _PredictionInputScreenState extends State<PredictionInputScreen> {
  DateTime? nextRaceDate;
  String? nextRaceName;
  Duration? timeUntilNextRace;
  bool raceStarted = false;
  Timer? countdownTimer;

  List<Map<String, String>> drivers =
      []; // List of drivers with 'code' and 'name'

  // Prediction variables
  String? selectedDriverTop1;
  String? selectedDriverTop2;
  String? selectedDriverTop3;
  String? selectedDriverTop4;
  String? selectedDriverTop5;
  String? selectedDriverSprintTop1;
  String? selectedDriverSprintTop2;
  String? selectedDriverSprintTop3;
  String? selectedDriverSprintQualiTop1;
  String? selectedDriverQualiTop1;
  String? selectedDriverQualiTop2;

  @override
  void initState() {
    super.initState();
    fetchNextRace();
    fetchDrivers();
  }

  @override
  void dispose() {
    if (countdownTimer != null) {
      countdownTimer!.cancel();
    }
    super.dispose();
  }

  Future<void> fetchNextRace() async {
    try {
      final response =
          await http.get(Uri.parse('https://ergast.com/api/f1/current.json'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final races = data['MRData']['RaceTable']['Races'];
        DateTime now = DateTime.now().toUtc();
        bool foundNextRace = false;
        for (var race in races) {
          // Log the race date and time for debugging
          print("Race date: ${race['date']} ${race['time']}");
          DateTime raceDateTime =
              DateTime.parse('${race['date']}T${race['time']}');
          if (raceDateTime.isAfter(now)) {
            setState(() {
              nextRaceDate = raceDateTime.toLocal();
              nextRaceName = race['raceName'];
            });
            print(nextRaceName);
            startCountdownTimer();
            foundNextRace = true;
            break;
          }
        }
        if (!foundNextRace) {
          // No upcoming races in current season
          setState(() {
            nextRaceDate = null;
            nextRaceName = "No upcoming races in the current season.";
          });
        }
      } else {
        throw Exception('Failed to load next race');
      }
    } catch (e) {
      print('Error fetching next race: $e');
      setState(() {
        nextRaceDate = null;
        nextRaceName = "Error fetching next race.";
      });
    }
  }

  Future<void> fetchDrivers() async {
    try {
      final response = await http.get(Uri.parse(
          'https://ergast.com/api/f1/current/last/drivers.json')); // Use a season with data
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          drivers = (data['MRData']['DriverTable']['Drivers'] as List<dynamic>)
              .map<Map<String, String>>((driver) => <String, String>{
                    'code':
                        (driver['code'] ?? driver['driverId'] ?? '').toString(),
                    'name': '${driver['givenName']} ${driver['familyName']}',
                  })
              .toList();
        });
      } else {
        throw Exception('Failed to load drivers');
      }
    } catch (e) {
      print('Error fetching drivers: $e');
      setState(() {
        drivers = [];
      });
    }
  }

  void startCountdownTimer() {
    if (nextRaceDate == null) return; // No upcoming race
    countdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (nextRaceDate != null) {
        setState(() {
          final now = DateTime.now();
          if (nextRaceDate!.isAfter(now)) {
            timeUntilNextRace = nextRaceDate!.difference(now);
            raceStarted = false;
          } else {
            timeUntilNextRace = Duration.zero;
            raceStarted = true;
            timer.cancel();
          }
        });
      }
    });
  }

  String formatDuration(Duration duration) {
    if (duration == null) return "";
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String days = duration.inDays.toString();
    String hours = twoDigits(duration.inHours.remainder(24));
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$days Days : $hours Hours : $minutes Minutes : $seconds Seconds";
  }

  Widget buildDriverDropdown({
    required String labelText,
    required String? value,
    required Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(labelText: labelText),
      value: value,
      items: drivers.map((driver) {
        return DropdownMenuItem<String>(
          value: driver['code'],
          child: Text(driver['name']!),
        );
      }).toList(),
      onChanged: raceStarted ? null : onChanged,
    );
  }

  Widget buildPredictionsInput() {
    return Column(
      children: [
        buildDriverDropdown(
          labelText: 'Top 1 Driver',
          value: selectedDriverTop1,
          onChanged: (value) {
            setState(() {
              selectedDriverTop1 = value;
            });
          },
        ),
        buildDriverDropdown(
          labelText: 'Top 2 Driver',
          value: selectedDriverTop2,
          onChanged: (value) {
            setState(() {
              selectedDriverTop2 = value;
            });
          },
        ),
        buildDriverDropdown(
          labelText: 'Top 3 Driver',
          value: selectedDriverTop3,
          onChanged: (value) {
            setState(() {
              selectedDriverTop3 = value;
            });
          },
        ),
        buildDriverDropdown(
          labelText: 'Top 4 Driver',
          value: selectedDriverTop4,
          onChanged: (value) {
            setState(() {
              selectedDriverTop4 = value;
            });
          },
        ),
        buildDriverDropdown(
          labelText: 'Top 5 Driver',
          value: selectedDriverTop5,
          onChanged: (value) {
            setState(() {
              selectedDriverTop5 = value;
            });
          },
        ),
        SizedBox(height: 20),
        Text(
          'Sprint Race Predictions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        buildDriverDropdown(
          labelText: 'Sprint Top 1 Driver',
          value: selectedDriverSprintTop1,
          onChanged: (value) {
            setState(() {
              selectedDriverSprintTop1 = value;
            });
          },
        ),
        buildDriverDropdown(
          labelText: 'Sprint Top 2 Driver',
          value: selectedDriverSprintTop2,
          onChanged: (value) {
            setState(() {
              selectedDriverSprintTop2 = value;
            });
          },
        ),
        buildDriverDropdown(
          labelText: 'Sprint Top 3 Driver',
          value: selectedDriverSprintTop3,
          onChanged: (value) {
            setState(() {
              selectedDriverSprintTop3 = value;
            });
          },
        ),
        buildDriverDropdown(
          labelText: 'Sprint Qualifying Top 1 Driver',
          value: selectedDriverSprintQualiTop1,
          onChanged: (value) {
            setState(() {
              selectedDriverSprintQualiTop1 = value;
            });
          },
        ),
        SizedBox(height: 20),
        Text(
          'Qualifying Predictions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        buildDriverDropdown(
          labelText: 'Qualifying Top 1 Driver',
          value: selectedDriverQualiTop1,
          onChanged: (value) {
            setState(() {
              selectedDriverQualiTop1 = value;
            });
          },
        ),
        buildDriverDropdown(
          labelText: 'Qualifying Top 2 Driver',
          value: selectedDriverQualiTop2,
          onChanged: (value) {
            setState(() {
              selectedDriverQualiTop2 = value;
            });
          },
        ),
        SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if ((nextRaceDate == null && nextRaceName == null) || drivers.isEmpty) {
      // Handle case where there is no upcoming race or drivers data
      return Scaffold(
        appBar: AppBar(
          title: Text('Prediction Input'),
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    } else {
      return Scaffold(
        appBar: AppBar(
          title: Text('Prediction Input'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(
                'Next Grand Prix: $nextRaceName',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              if (nextRaceDate != null)
                Column(
                  children: [
                    Text(
                      'Next Race Countdown:',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      formatDuration(timeUntilNextRace!),
                      style: TextStyle(fontSize: 20),
                    ),
                    SizedBox(height: 20),
                    buildPredictionsInput(),
                  ],
                )
              else
                Text(
                  'No upcoming races.',
                  style: TextStyle(fontSize: 18),
                ),
            ],
          ),
        ),
      );
    }
  }
}
