import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageController extends ChangeNotifier {
  LanguageController._();
  static final LanguageController instance = LanguageController._();

  static const _kLocaleCodeKey = 'app_locale_code';
  Locale? _locale;
  Locale? get locale => _locale;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kLocaleCodeKey);
    _locale = (code == null || code.isEmpty) ? null : Locale(code);
  }

  Future<void> setLocale(Locale? newLocale) async {
    _locale = newLocale;
    final prefs = await SharedPreferences.getInstance();
    if (newLocale == null) {
      await prefs.remove(_kLocaleCodeKey);
    } else {
      await prefs.setString(_kLocaleCodeKey, newLocale.languageCode);
    }
    notifyListeners();
  }
}
