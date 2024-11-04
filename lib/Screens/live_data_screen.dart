import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class LiveDataPage extends StatefulWidget {
  @override
  _LiveDataPageState createState() => _LiveDataPageState();
}

class _LiveDataPageState extends State<LiveDataPage> {
  List<Map<String, dynamic>> _leaderboard = [];
  bool _isLoading = true;
  String _raceName = '';
  String _raceStatus = ''; // can be "live", "finished", or "upcoming"
  String _season = '';
  int? _expandedIndex;

  List<String> _seasons = [];
  String? _selectedSeason;

  List<Map<String, dynamic>> _races =
      []; // Each race will have 'round', 'raceName', and 'hasSprint'
  String? _selectedRound;

  String _selectedSessionType = 'results'; // 'results', 'qualifying', 'sprint'
  List<String> _availableSessionTypes = ['results', 'qualifying'];

  // Define team colors (these are sample colors, customize as needed)
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
    // Fetch data for the current/last race only
    fetchCurrentOrLastRace();
  }

  Future<void> fetchCurrentOrLastRace() async {
    try {
      // Fetch the last race results
      final response = await http.get(
          Uri.parse('https://ergast.com/api/f1/current/last/results.json'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final race = data['MRData']['RaceTable']['Races'][0];

        setState(() {
          _raceName = race['raceName'];
          _season = race['season'];
          _raceStatus = _getRaceStatus(race['date'], race['time']);
          _selectedSeason = _season;
          _selectedRound = race['round'];
        });

        // Parse results to create leaderboard
        final List<dynamic> results = race['Results'];
        setState(() {
          _leaderboard = results.map((result) {
            final driver = result['Driver'];
            final constructor = result['Constructor'];
            return {
              'position': result['position'],
              'driver': '${driver['givenName']} ${driver['familyName']}',
              'team': constructor['name'],
              'teamCode': constructor['constructorId'],
              'points': result['points'],
              'laps': result['laps'],
              'code': driver['code'],
              'status': result['status'],
              'grid': result['grid'],
              'time': result['Time']?['time'] ?? 'N/A',
              'fastestLap': result['FastestLap']?['lap'] ?? 'N/A',
              'fastestLapTime': result['FastestLap']?['Time']?['time'] ?? 'N/A',
              'fastestLapSpeed':
                  result['FastestLap']?['AverageSpeed']?['speed'] ?? 'N/A',
            };
          }).toList();
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load current/last race data');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Error fetching current/last race data: $e');
    }
  }

  Future<void> fetchSeasons() async {
    try {
      final response = await http
          .get(Uri.parse('https://ergast.com/api/f1/seasons.json?limit=1000'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final seasonsData = data['MRData']['SeasonTable']['Seasons'];
        setState(() {
          _seasons = seasonsData
              .map<String>((season) => season['season'].toString())
              .toList()
              .reversed
              .toList(); // Reverse to have latest seasons first
        });
      } else {
        throw Exception('Failed to load seasons');
      }
    } catch (e) {
      print('Error fetching seasons: $e');
    }
  }

  Future<void> fetchRacesForSeason(String season) async {
    try {
      final response =
          await http.get(Uri.parse('https://ergast.com/api/f1/$season.json'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final racesData = data['MRData']['RaceTable']['Races'];
        setState(() {
          _races = racesData.map<Map<String, dynamic>>((race) {
            return {
              'round': race['round'],
              'raceName': race['raceName'],
              'hasSprint': false, // We'll update this shortly
            };
          }).toList();
        });
        await checkForSprints(season);
      } else {
        throw Exception('Failed to load races for season $season');
      }
    } catch (e) {
      print('Error fetching races for season $season: $e');
    }
  }

  Future<void> checkForSprints(String season) async {
    // Check which races have sprint events
    List<Future<void>> futures = [];
    for (var race in _races) {
      futures.add(http
          .get(Uri.parse(
              'https://ergast.com/api/f1/$season/${race['round']}/sprint.json'))
          .then((response) {
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['MRData']['RaceTable']['Races'].isNotEmpty) {
            // Sprint data exists for this race
            setState(() {
              race['hasSprint'] = true;
            });
          }
        }
      }).catchError((e) {
        print('Error checking sprint for race ${race['round']}: $e');
      }));
    }
    await Future.wait(futures);
  }

  Future<void> fetchLeaderboard() async {
    if (_selectedSeason == null || _selectedRound == null) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String sessionTypeEndpoint = _selectedSessionType;
      if (_selectedSessionType == 'sprint') {
        sessionTypeEndpoint = 'sprint';
      }
      String url =
          'https://ergast.com/api/f1/$_selectedSeason/$_selectedRound/$sessionTypeEndpoint.json';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Fetch race name, season, and determine status
        final raceTable = data['MRData']['RaceTable'];
        if (raceTable['Races'].isEmpty) {
          setState(() {
            _isLoading = false;
            _leaderboard = [];
            _raceName = '';
            _season = '';
            _raceStatus = '';
          });
          return;
        }
        final race = raceTable['Races'][0];
        setState(() {
          _raceName = race['raceName'];
          _season = race['season'];
          _raceStatus = _getRaceStatus(race['date'], race['time']);
        });

        // Parse results to create leaderboard
        List<dynamic> results;
        if (_selectedSessionType == 'results') {
          results = race['Results'];
        } else if (_selectedSessionType == 'sprint') {
          results = race['SprintResults'] ?? race['Results'] ?? [];
        } else if (_selectedSessionType == 'qualifying') {
          results = race['QualifyingResults'];
        } else {
          results = [];
        }

        setState(() {
          _leaderboard = results.map((result) {
            // Parse result data according to the session type
            final driver = result['Driver'];
            final constructor = result['Constructor'];
            Map<String, dynamic> item = {
              'position': result['position'],
              'driver': '${driver['givenName']} ${driver['familyName']}',
              'team': constructor['name'],
              'teamCode': constructor['constructorId'],
              'code': driver['code'],
            };
            if (_selectedSessionType == 'results' ||
                _selectedSessionType == 'sprint') {
              item.addAll({
                'points': result['points'],
                'laps': result['laps'],
                'status': result['status'],
                'grid': result['grid'],
                'time': result['Time']?['time'] ?? 'N/A',
                'fastestLap': result['FastestLap']?['lap'] ?? 'N/A',
                'fastestLapTime':
                    result['FastestLap']?['Time']?['time'] ?? 'N/A',
                'fastestLapSpeed':
                    result['FastestLap']?['AverageSpeed']?['speed'] ?? 'N/A',
              });
            } else if (_selectedSessionType == 'qualifying') {
              item.addAll({
                'q1': result['Q1'] ?? 'N/A',
                'q2': result['Q2'] ?? 'N/A',
                'q3': result['Q3'] ?? 'N/A',
              });
            }
            return item;
          }).toList();
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load leaderboard');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Error fetching leaderboard: $e');
    }
  }

  String _getRaceStatus(String date, String time) {
    final raceDateTime = DateTime.parse('$date $time');
    final now = DateTime.now();

    if (now.isBefore(raceDateTime)) {
      return 'upcoming';
    } else if (now.isAfter(raceDateTime.add(Duration(hours: 2)))) {
      return 'finished';
    } else {
      return 'live';
    }
  }

  List<Widget> _buildExpandedItemDetails(Map<String, dynamic> item) {
    List<Widget> details = [];
    if (_selectedSessionType == 'results' || _selectedSessionType == 'sprint') {
      details.addAll([
        Text('Laps: ${item['laps']}'),
        Text('Status: ${item['status']}'),
        Text('Starting Grid Position: ${item['grid']}'),
        Text('Time: ${item['time']}'),
        Text('Fastest Lap: ${item['fastestLap']}'),
        Text('Fastest Lap Time: ${item['fastestLapTime']}'),
        Text('Fastest Lap Speed: ${item['fastestLapSpeed']}'),
      ]);
    } else if (_selectedSessionType == 'qualifying') {
      details.addAll([
        Text('Q1 Time: ${item['q1']}'),
        Text('Q2 Time: ${item['q2']}'),
        Text('Q3 Time: ${item['q3']}'),
      ]);
    }
    return details;
  }

  Future<void> _onSeasonDropdownTap() async {
    if (_seasons.isEmpty) {
      setState(() {
        _isLoading = true;
      });
      await fetchSeasons();
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _onRaceDropdownTap() async {
    if (_selectedSeason == null) return;

    if (_races.isEmpty) {
      setState(() {
        _isLoading = true;
      });
      await fetchRacesForSeason(_selectedSeason!);
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _updateAvailableSessionTypes() {
    setState(() {
      _availableSessionTypes = ['results', 'qualifying'];
      if (_selectedRaceHasSprint()) {
        _availableSessionTypes.add('sprint');
      }
      if (!_availableSessionTypes.contains(_selectedSessionType)) {
        _selectedSessionType = _availableSessionTypes.first;
      }
    });
  }

  bool _selectedRaceHasSprint() {
    if (_races.isEmpty || _selectedRound == null) return false;
    var race = _races.firstWhere(
      (race) => race['round'] == _selectedRound,
      orElse: () => {},
    );
    if (race != null) {
      return race['hasSprint'] ?? false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Adjust the AppBar height using PreferredSize
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(144.0), // Adjusted height
        child: AppBar(
          // Use a Column to stack the dropdowns vertically
          flexibleSpace: Padding(
            padding: const EdgeInsets.only(top: 40.0, left: 8.0, right: 8.0),
            child: Column(
              children: [
                // Season and Race Dropdowns
                Row(
                  children: [
                    // Season Dropdown
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          await _onSeasonDropdownTap();
                        },
                        child: AbsorbPointer(
                          absorbing: _seasons.isEmpty,
                          child: DropdownButton<String>(
                            isExpanded: true,
                            hint: Text('Season'),
                            value: _selectedSeason,
                            items: _seasons.map((season) {
                              return DropdownMenuItem<String>(
                                value: season,
                                child: Text(season),
                              );
                            }).toList(),
                            onChanged: (value) async {
                              setState(() {
                                _selectedSeason = value;
                                _selectedRound = null;
                                _races = [];
                                _leaderboard = [];
                                _raceName = '';
                                _isLoading = true;
                              });
                              await fetchRacesForSeason(value!);
                              _updateAvailableSessionTypes();
                              setState(() {
                                _isLoading = false;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    // Race Dropdown
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          await _onRaceDropdownTap();
                        },
                        child: AbsorbPointer(
                          absorbing: _races.isEmpty,
                          child: DropdownButton<String>(
                            isExpanded: true,
                            hint: Text('Race'),
                            value: _selectedRound,
                            items: _races.map((race) {
                              return DropdownMenuItem<String>(
                                value: race['round'],
                                child: Text(race['raceName']),
                              );
                            }).toList(),
                            onChanged: (value) async {
                              setState(() {
                                _selectedRound = value;
                                _leaderboard = [];
                                _isLoading = true;
                              });
                              _updateAvailableSessionTypes();
                              await fetchLeaderboard();
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                // Session Type Dropdown
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedSessionType,
                        items: _availableSessionTypes.map((sessionType) {
                          String displayText;
                          if (sessionType == 'results') {
                            displayText = 'Race Results';
                          } else if (sessionType == 'qualifying') {
                            displayText = 'Qualification';
                          } else if (sessionType == 'sprint') {
                            displayText = 'Sprint Race';
                          } else {
                            displayText = sessionType;
                          }
                          return DropdownMenuItem(
                            value: sessionType,
                            child: Text(displayText),
                          );
                        }).toList(),
                        onChanged: (value) async {
                          setState(() {
                            _selectedSessionType = value!;
                            _leaderboard = [];
                            _isLoading = true;
                          });
                          await fetchLeaderboard();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Race Name and Status
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Text(
                        _raceName,
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(width: 10),
                      if (_raceStatus == 'live')
                        Icon(Icons.circle, color: Colors.red, size: 10)
                      else if (_raceStatus == 'finished')
                        Text('Finished', style: TextStyle(color: Colors.grey))
                      else if (_raceStatus == 'upcoming')
                        Text('Upcoming', style: TextStyle(color: Colors.blue)),
                    ],
                  ),
                ),
                // Expanded ListView of leaderboard
                Expanded(
                  child: _leaderboard.isEmpty
                      ? Center(child: Text('No data available'))
                      : ListView.builder(
                          itemCount: _leaderboard.length,
                          itemBuilder: (context, index) {
                            final item = _leaderboard[index];
                            final isExpanded = _expandedIndex == index;
                            final teamColor =
                                _teamColors[item['teamCode']] ?? Colors.black;

                            return Column(
                              children: [
                                ListTile(
                                  leading: Text(item['position']),
                                  title: Text(
                                    isExpanded
                                        ? item['driver'] ?? 'Unknown Driver'
                                        : item['code'] ?? 'Unknown Driver',
                                    style: TextStyle(
                                        color: teamColor,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    item['team'] ?? 'Unknown Team',
                                  ),
                                  trailing: Text(
                                    (_selectedSessionType == 'results' ||
                                            _selectedSessionType == 'sprint')
                                        ? 'Points: ${item['points'] ?? '0'}'
                                        : '',
                                  ),
                                  onTap: () {
                                    setState(() {
                                      _expandedIndex =
                                          isExpanded ? null : index;
                                    });
                                  },
                                ),
                                if (isExpanded)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: _buildExpandedItemDetails(item),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
