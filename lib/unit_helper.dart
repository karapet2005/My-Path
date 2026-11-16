import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UnitHelper {
  static final UnitHelper instance = UnitHelper._init();
  UnitHelper._init();

  final ValueNotifier<bool> useMilesNotifier = ValueNotifier<bool>(false);

  bool get useMiles => useMilesNotifier.value;

  Future<void> loadUnitPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('use_miles')) {
      useMilesNotifier.value = prefs.getBool('use_miles') ?? false;
    } else {
      String defaultLang = prefs.getString('app_language') ?? 'de';
      useMilesNotifier.value = (defaultLang == 'en'); 
    }
  }

  Future<void> setUseMiles(bool value) async {
    useMilesNotifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_miles', value);
  }

  double formatDistance(double km) {
    if (useMilesNotifier.value) {
      return km * 0.621371;
    }
    return km;
  }

  String getUnitLabel() {
    return useMilesNotifier.value ? 'mi' : 'km';
  }
}