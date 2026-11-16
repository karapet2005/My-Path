import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';
import 'fog_tab.dart';
import 'planning_tab.dart';
import 'stats_tab.dart';
import 'settings_tab.dart';
import 'app_localizations.dart';
import 'unit_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.instance.database;
  await UnitHelper.instance.loadUnitPreference();
  runApp(const PathTrackerApp());
}

class PathTrackerApp extends StatefulWidget {
  const PathTrackerApp({super.key});

  static void setLocale(BuildContext context, String newLocale) {
    final _PathTrackerAppState? state = context.findAncestorStateOfType<_PathTrackerAppState>();
    state?.changeLanguage(newLocale);
  }

  @override
  State<PathTrackerApp> createState() => _PathTrackerAppState();
}

class _PathTrackerAppState extends State<PathTrackerApp> {
  String _currentLocale = 'de';

  @override
  void initState() {
    super.initState();
    _loadSavedLanguage();
  }

  Future<void> _loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString('app_language');
    if (savedLang != null) {
      setState(() {
        _currentLocale = savedLang;
      });
    }
  }

  void changeLanguage(String newLocale) async {
    setState(() {
      _currentLocale = newLocale;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', newLocale);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Path',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0C12),
        primarySwatch: Colors.green,
      ),
      home: MainScreen(currentLocale: _currentLocale),
    );
  }
}

class MainScreen extends StatefulWidget {
  final String currentLocale;
  const MainScreen({super.key, required this.currentLocale});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations(widget.currentLocale);

    // HIER DER FIX: IndexedStack hält alle Tabs dauerhaft im Speicher und aktiv!
    final List<Widget> tabs = [
      FogOfWarTab(currentLocale: widget.currentLocale),
      PlanningTab(currentLocale: widget.currentLocale),
      StatsTab(currentLocale: widget.currentLocale),
      SettingsTab(currentLocale: widget.currentLocale),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        backgroundColor: const Color(0xFF121620),
        selectedItemColor: Colors.greenAccent,
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.explore), label: t.translate('tabProgress')),
          BottomNavigationBarItem(icon: const Icon(Icons.map), label: t.translate('tabPlanning')),
          BottomNavigationBarItem(icon: const Icon(Icons.bar_chart), label: t.translate('tabStats')),
          BottomNavigationBarItem(icon: const Icon(Icons.settings), label: t.translate('tabSettings')),
        ],
      ),
    );
  }
}