import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class LiveTableScreen extends StatefulWidget {
  @override
  _LiveTableScreenState createState() => _LiveTableScreenState();
}

class _LiveTableScreenState extends State<LiveTableScreen> {
  List<dynamic> driverStandings = [];
  List<Map<String, dynamic>> predictionStandings = [];

  // Define team colors
  final Map<String, Color> _teamColors = {
    'mercedes': Colors.teal, // Mercedes
    'ferrari': Colors.red, // Ferrari
    'red_bull': Colors.blue, // Red Bull Racing
    'mclaren': Colors.orange, // McLaren
    'aston_martin': Colors.green, // Aston Martin
    'alpine': Colors.blueAccent, // Alpine
    'alphatauri': Colors.indigo, // AlphaTauri
    'alfa': Colors.redAccent, // Alfa Romeo
    'haas': Colors.grey, // Haas
    'williams': Colors.lightBlue, // Williams
  };

  @override
  void initState() {
    super.initState();
    fetchDriverStandings();
    fetchPredictionStandings();
  }

  Future<void> fetchDriverStandings() async {
    final response = await http.get(
        Uri.parse('https://ergast.com/api/f1/current/driverStandings.json'));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        driverStandings = data['MRData']['StandingsTable']['StandingsLists'][0]
            ['DriverStandings'];
      });
    } else {
      throw Exception('Failed to load driver standings');
    }
  }

  void fetchPredictionStandings() {
    // Create mock data for predictions
    setState(() {
      predictionStandings = [
        {'name': 'Anton', 'points': 120},
        {'name': 'Lukas', 'points': 110},
        {'name': 'Simon', 'points': 90},
        {'name': 'Paul', 'points': 80},
        {'name': 'Peter', 'points': 70},
      ];
    });
  }

  Widget buildStandings(List standings, {bool isDriverStandings = true}) {
    return standings.isEmpty
        ? Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            child: Column(
              children: [
                // Podium for the top 3
                buildPodium(standings, isDriverStandings),
                // Remaining standings
                ListView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: standings.length - 3,
                  itemBuilder: (context, index) {
                    if (isDriverStandings) {
                      // Driver standings
                      final driver = standings[index + 3]['Driver'];
                      final constructor =
                          standings[index + 3]['Constructors'][0];
                      final position = standings[index + 3]['position'];
                      final points = standings[index + 3]['points'];
                      final teamId = constructor['constructorId'];

                      final teamColor = _teamColors[teamId] ?? Colors.black;

                      return ListTile(
                        leading: Text(position),
                        title: Text(
                          '${driver['givenName']} ${driver['familyName']}',
                          style: TextStyle(
                            color: teamColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text('Points: $points'),
                      );
                    } else {
                      // Prediction standings
                      final position = (index + 4).toString();
                      final player = standings[index + 3];
                      final name = player['name'];
                      final points = player['points'];

                      return ListTile(
                        leading: Text(position),
                        title: Text(
                          name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text('Points: $points'),
                      );
                    }
                  },
                ),
              ],
            ),
          );
  }

  Widget buildPodium(List standings, bool isDriverStandings) {
    if (standings.length < 3) {
      return SizedBox();
    }

    // Get top 3
    final first = standings[0];
    final second = standings[1];
    final third = standings[2];

    // Helper to get info
    Widget podiumPlace(
        Map<String, dynamic> standing, int place, double height) {
      String name;
      String points;
      Color color = Colors.black;

      if (isDriverStandings) {
        final driver = standing['Driver'];
        final constructor = standing['Constructors'][0];
        final teamId = constructor['constructorId'];
        name = '${driver['givenName']} ${driver['familyName']}';
        points = standing['points'];
        color = _teamColors[teamId] ?? Colors.black;
      } else {
        name = standing['name'];
        points = standing['points'].toString();
      }

      return Column(
        children: [
          Container(
            height: height,
            width: 80,
            color: Colors.grey.shade300,
            child: Center(
              child: Text(
                '$place',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Container(
            width: 80,
            color: Colors.white,
            child: Column(
              children: [
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Points: $points',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Second place
          podiumPlace(second, 2, 120),
          SizedBox(width: 10),
          // First place
          podiumPlace(first, 1, 150),
          SizedBox(width: 10),
          // Third place
          podiumPlace(third, 3, 100),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, // Number of tabs
      child: Scaffold(
        appBar: AppBar(
          title: Text('Standings'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Driver Standings'),
              Tab(text: 'Predictions'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // First tab content - driver standings
            buildStandings(driverStandings, isDriverStandings: true),
            // Second tab content - prediction standings
            buildStandings(predictionStandings, isDriverStandings: false),
          ],
        ),
      ),
    );
  }
}
