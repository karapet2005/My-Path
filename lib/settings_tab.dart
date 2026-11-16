import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import 'app_localizations.dart';
import 'unit_helper.dart';

class SettingsTab extends StatefulWidget {
  final String currentLocale;
  const SettingsTab({super.key, required this.currentLocale});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  bool _audioEnabled = true;
  bool _useMiles = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await UnitHelper.instance.loadUnitPreference();
    setState(() {
      _audioEnabled = prefs.getBool('audio_enabled') ?? true;
      _useMiles = UnitHelper.instance.useMiles;
    });
  }

  Future<void> _setAudioEnabled(bool value) async {
    setState(() {
      _audioEnabled = value;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('audio_enabled', value);
  }

  Future<void> _setUseMiles(bool value) async {
    setState(() {
      _useMiles = value;
    });
    await UnitHelper.instance.setUseMiles(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations(widget.currentLocale);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.translate('tabSettings'), style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF121620),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white12),
              ),
              child: SwitchListTile(
                title: Text(t.translate('audioFeedback'), style: const TextStyle(color: Colors.white, fontSize: 15)),
                value: _audioEnabled,
                activeTrackColor: Colors.greenAccent,
                onChanged: _setAudioEnabled,
              ),
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF121620),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white12),
              ),
              child: SwitchListTile(
                title: Text(t.translate('unitSetting'), style: const TextStyle(color: Colors.white, fontSize: 15)),
                subtitle: Text(_useMiles ? 'Miles (mi)' : 'Kilometers (km)', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                value: _useMiles,
                activeTrackColor: Colors.greenAccent,
                onChanged: _setUseMiles,
              ),
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF121620),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.language, color: Colors.greenAccent),
                      const SizedBox(width: 15),
                      Text(t.translate('language'), style: const TextStyle(color: Colors.white, fontSize: 16)),
                    ],
                  ),
                  DropdownButton<String>(
                    value: widget.currentLocale,
                    dropdownColor: const Color(0xFF121620),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                      DropdownMenuItem(value: 'en', child: Text('English')),
                      DropdownMenuItem(value: 'es', child: Text('Español')),
                      DropdownMenuItem(value: 'fr', child: Text('Français')),
                    ],
                    onChanged: (String? newLang) {
                      if (newLang != null) {
                        PathTrackerApp.setLocale(context, newLang);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}