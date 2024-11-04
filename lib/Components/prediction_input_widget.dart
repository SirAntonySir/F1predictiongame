import 'package:flutter/material.dart';

class PredictionInputWidget extends StatelessWidget {
  final List<Map<String, dynamic>> drivers;
  final Function(String?) onDriverSelected;
  final String? selectedDriver;

  PredictionInputWidget({
    required this.drivers,
    required this.onDriverSelected,
    this.selectedDriver,
  });

  final Map<String, Color> _teamColors = {
    'mercedes': Colors.teal,
    'ferrari': Colors.red,
    'red_bull': Colors.blue,
    'mclaren': Colors.orange,
    'aston_martin': Colors.green,
    'alpine': Colors.blueAccent,
    'alphatauri': Colors.indigo,
    'alfa': Colors.redAccent,
    'haas': Colors.grey,
    'williams': Colors.lightBlue,
  };

  Color _getTeamColor(String? teamId) {
    return _teamColors[teamId?.toLowerCase()] ?? Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120, // Adjust height based on item size
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: (drivers.length / 2).ceil(),
        itemBuilder: (context, index) {
          final firstDriverIndex = index * 2;
          final secondDriverIndex = firstDriverIndex + 1;

          return Column(
            children: [
              if (firstDriverIndex < drivers.length)
                _buildDriverItem(drivers[firstDriverIndex]),
              SizedBox(height: 10), // Adjust spacing between rows
              if (secondDriverIndex < drivers.length)
                _buildDriverItem(drivers[secondDriverIndex]),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDriverItem(Map<String, dynamic> driver) {
    final driverCode = driver['code'] ?? '';
    final teamColor = _getTeamColor(driver['team']);
    final isSelected = selectedDriver == driverCode;

    return GestureDetector(
      onTap: () => onDriverSelected(driverCode),
      child: Container(
        width: 60, // Adjust width based on screen width or requirements
        height: 50, // Adjust height based on item size
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: isSelected ? teamColor : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(
                  color: teamColor,
                  width: 2,
                )
              : Border.all(
                  color: teamColor.withOpacity(0.5),
                  width: 2,
                ),
        ),
        child: Center(
          child: Text(
            driverCode,
            style: TextStyle(
              color: isSelected ? Colors.white : teamColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
