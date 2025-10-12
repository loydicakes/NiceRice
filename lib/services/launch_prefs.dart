import 'package:shared_preferences/shared_preferences.dart';

class LaunchPrefs {
  static const _kHasSeenIntro = 'has_seen_intro_v1';
  static const _kLastRoute = 'last_route_v1';
  static const _kLastTabIndex = 'last_tab_index_v1';

  static Future<bool> get hasSeenIntro async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kHasSeenIntro) ?? false;
  }

  static Future<void> setHasSeenIntro() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kHasSeenIntro, true);
  }

  static Future<String?> getLastRoute() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLastRoute);
  }

  static Future<void> saveLastRoute(String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLastRoute, name);
  }

  static Future<int?> getLastTabIndex() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kLastTabIndex);
  }

  static Future<void> saveLastTabIndex(int i) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kLastTabIndex, i);
  }

  static Future<void> clearOnSignOut() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kLastRoute);
    await p.remove(_kLastTabIndex);
  }
}
