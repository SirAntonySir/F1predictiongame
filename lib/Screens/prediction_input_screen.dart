import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:predictiongame/Components/countdown_widget.dart';
import 'package:predictiongame/Components/prediction_input_widget.dart';

class PredictionInputScreen extends StatefulWidget {
  @override
  _PredictionInputScreenState createState() => _PredictionInputScreenState();
}

class _PredictionInputScreenState extends State<PredictionInputScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  DateTime? nextRaceDate;
  String? nextRaceName;
  Duration? timeUntilNextRace;
  bool raceStarted = false;
  Timer? countdownTimer;

  List<Map<String, dynamic>> drivers = [];
  String? selectedDriverTop1;
  String? selectedDriverTop2;

  @override
  void initState() {
    super.initState();
    fetchNextRace();
    fetchDrivers();
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    super.dispose();
  }

  void startCountdownTimer() {
    if (nextRaceDate == null) return;
    countdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
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
    });
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
          DateTime raceDateTime =
              DateTime.parse('${race['date']}T${race['time']}');
          if (raceDateTime.isAfter(now)) {
            setState(() {
              nextRaceDate = raceDateTime.toLocal();
              nextRaceName = race['raceName'];
            });
            startCountdownTimer();
            foundNextRace = true;
            break;
          }
        }
        if (!foundNextRace) {
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
      final response = await http.get(
          Uri.parse('https://ergast.com/api/f1/current/driverStandings.json'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final standingsList = data['MRData']['StandingsTable']['StandingsLists']
            [0]['DriverStandings'];

        setState(() {
          drivers = standingsList.map<Map<String, dynamic>>((driverStanding) {
            final driver = driverStanding['Driver'];
            final constructor = driverStanding['Constructors'][0];
            return {
              'code': driver['code'] ?? driver['driverId'],
              'name': '${driver['givenName']} ${driver['familyName']}',
              'team': constructor['constructorId'],
              'position': driverStanding['position'].toString(),
              'points': driverStanding['points'].toString(),
            };
          }).toList();
        });
      } else {
        throw Exception('Failed to load driver standings');
      }
    } catch (e) {
      print('Error fetching driver standings: $e');
      setState(() {
        drivers = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Prediction Input'),
      ),
      body: drivers.isEmpty
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text(
                    '$nextRaceName',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 10),
                  CountdownWidget(
                    timeUntilNextRace: timeUntilNextRace,
                    raceStarted: raceStarted,
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Top 1 Driver',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  PredictionInputWidget(
                    drivers: drivers,
                    onDriverSelected: (driver) {
                      setState(() {
                        selectedDriverTop1 = driver;
                      });
                    },
                    selectedDriver: selectedDriverTop1,
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Top 2 Driver',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  PredictionInputWidget(
                    drivers: drivers,
                    onDriverSelected: (driver) {
                      setState(() {
                        selectedDriverTop2 = driver;
                      });
                    },
                    selectedDriver: selectedDriverTop2,
                  ),
                ],
              ),
            ),
    );
  }
}
