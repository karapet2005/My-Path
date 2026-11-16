import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'app_localizations.dart';
import 'unit_helper.dart';

class StatsTab extends StatefulWidget {
  final String currentLocale;
  const StatsTab({super.key, required this.currentLocale});

  @override
  State<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<StatsTab> {
  double _totalKm = 0.0;
  int _totalTiles = 0;
  int _streak = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
    // Hört sofort zu, wenn sich die Einheit ändert!
    UnitHelper.instance.useMilesNotifier.addListener(_onUnitChanged);
  }

  @override
  void dispose() {
    UnitHelper.instance.useMilesNotifier.removeListener(_onUnitChanged);
    super.dispose();
  }

  void _onUnitChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadStats() async {
    final km = await DatabaseHelper.instance.getTotalKm();
    final tiles = await DatabaseHelper.instance.getExploredTilesCount();
    final streakCount = await DatabaseHelper.instance.getStreak();

    if (!mounted) return;
    setState(() {
      _totalKm = km;
      _totalTiles = tiles;
      _streak = streakCount;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations(widget.currentLocale);
    final formattedDist = UnitHelper.instance.formatDistance(_totalKm);
    final unit = UnitHelper.instance.getUnitLabel();

    return Scaffold(
      appBar: AppBar(
        title: Text(t.translate('statsTitle'), style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildStatCard(t.translate('total'), "${formattedDist.toStringAsFixed(2)} $unit", Icons.straighten, Colors.greenAccent),
            const SizedBox(height: 15),
            _buildStatCard(t.translate('exploredArea'), "${(_totalTiles * 0.01).toStringAsFixed(2)} km²", Icons.public, Colors.blueAccent),
            const SizedBox(height: 15),
            _buildStatCard(t.translate('unlockedTiles'), "$_totalTiles", Icons.grid_view, Colors.purpleAccent),
            const SizedBox(height: 15),
            _buildStatCard(t.translate('currentStreak'), "$_streak ${t.translate('days')}", Icons.local_fire_department, Colors.orangeAccent),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121620),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(15)),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 15),
              Text(title, style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}