import 'package:flutter/widgets.dart';
import 'launch_prefs.dart';

class RouteLogger extends NavigatorObserver {
  void _save(Route<dynamic>? r) {
    final name = r?.settings.name;
    if (name != null && name.isNotEmpty) {
      LaunchPrefs.saveLastRoute(name);
    }
  }

  @override
  void didPush(Route route, Route<dynamic>? previousRoute) => _save(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _save(newRoute);
  @override
  void didPop(Route route, Route<dynamic>? previousRoute) => _save(previousRoute);
}
