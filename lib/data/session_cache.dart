import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SessionCache {
  static const _k = 'automation.session';

  static Future<void> save(Map<String, dynamic> json) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_k, jsonEncode(json));
  }

  static Future<Map<String, dynamic>?> load() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_k);
    if (s == null) return null;
    try { return jsonDecode(s) as Map<String, dynamic>; } catch (_) { return null; }
  }

  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_k);
  }
}
