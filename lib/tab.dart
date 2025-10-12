// lib/tab.dart
// Responsive glass pill bottom navigation with dark-mode support
// and safe spacing so it never overlaps page content.

import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Your pages
import 'package:nice_rice/pages/homepage/home_page.dart';
import 'package:nice_rice/pages/automation/automation.dart';
import 'package:nice_rice/pages/analytics/analytics.dart';

// NEW: remember last tab index
import 'services/launch_prefs.dart';

class AppShell extends StatefulWidget {
  /// 0 = Home, 1 = Automation, 2 = Analytics (if signed-in)
  final int initialIndex;
  const AppShell({super.key, this.initialIndex = 0});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // Base pill sizing (actual usable height is adapted at runtime)
  static const double _pillBaseHeight = 64;
  static const double _hMargin = 16;
  static const double _bottomGap = 12;

  late final PageController _pageController;
  late final Stream<User?> _authStream;
  User? _user;
  int _index = 0;

  bool get _signedIn => _user != null;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
    _authStream = FirebaseAuth.instance.authStateChanges();
    _user = FirebaseAuth.instance.currentUser;

    // Restore last tab (async)
    _restoreTab();
  }

  Future<void> _restoreTab() async {
    final last = await LaunchPrefs.getLastTabIndex();
    if (!mounted) return;
    if (last != null) {
      final clamped = _clampIndex(last);
      // Jump without animation at startup for a snappy feel
      _index = clamped;
      _pageController.jumpToPage(clamped);
      setState(() {});
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<Widget> get _pages => _signedIn
      ? const [HomePage(), AutomationPage(), AnalyticsPage()]
      : const [HomePage(), AutomationPage()];

  int _clampIndex(int i) {
    final max = _pages.length - 1;
    if (i < 0) return 0;
    if (i > max) return max;
    return i;
  }

  // Jump (no animation) and persist
  void _jumpTo(int i) async {
    final t = _clampIndex(i);
    _index = t;
    if (_pageController.hasClients) {
      _pageController.jumpToPage(t);
    }
    setState(() {});
    await LaunchPrefs.saveLastTabIndex(t);
  }

  // Animate and persist
  void _onTapTab(int i) async {
    final t = _clampIndex(i);
    setState(() => _index = t);
    _pageController.animateToPage(
      t,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    await LaunchPrefs.saveLastTabIndex(t);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final safeBottom = mq.padding.bottom;

    // Grow the pill slightly for large accessibility text
    final textScale = mq.textScaler.scale(1.0); // 1.0..N
    final pillHeight = _pillBaseHeight + (textScale - 1.0) * 10.0;

    // Reserve space so pages never get under the pill
    final reservedBottom = pillHeight + _bottomGap + safeBottom + 8;

    return StreamBuilder<User?>(
      stream: _authStream,
      initialData: _user,
      builder: (_, snap) {
        _user = snap.data;

        // Keep a valid index when auth state changes
        if (_index >= _pages.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _jumpTo(_pages.length - 1); // also persists
          });
        }

        return Scaffold(
          extendBody: true,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Stack(
            children: [
              // Pages (with bottom padding so pill never overlaps)
              Padding(
                padding: EdgeInsets.only(bottom: reservedBottom),
                child: PageView(
                  controller: _pageController,
                  physics: const BouncingScrollPhysics(),
                  onPageChanged: (i) async {
                    setState(() => _index = i);
                    await LaunchPrefs.saveLastTabIndex(i); // persist swipe
                  },
                  children: _pages,
                ),
              ),

              // Floating glass pill nav
              Positioned(
                left: _hMargin,
                right: _hMargin,
                bottom: _bottomGap + safeBottom,
                child: _GlassNavBar(
                  height: pillHeight,
                  index: _index,
                  onSelect: _onTapTab,
                  showAnalytics: _signedIn,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// -------------------- Bottom Nav --------------------

class _GlassNavBar extends StatelessWidget {
  const _GlassNavBar({
    required this.height,
    required this.index,
    required this.onSelect,
    required this.showAnalytics,
  });

  final double height;
  final int index;
  final ValueChanged<int> onSelect;
  final bool showAnalytics;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Match your Canva style: green selected, muted gray unselected
    final selectedColor =
        isDark ? const Color(0xFF77C08A) : const Color(0xFF2E6B3A);
    final unselectedColor = cs.onSurface.withOpacity(isDark ? 0.55 : 0.45);

    final items = <_NavItemData>[
      const _NavItemData(icon: Icons.home_rounded, label: 'Home'),
      const _NavItemData(icon: Icons.tune_rounded, label: 'Automation'),
      if (showAnalytics)
        const _NavItemData(icon: Icons.analytics_rounded, label: 'Analytics'),
    ];

    // Cap internal text scale so labels don’t overflow
    final outer = MediaQuery.of(context).textScaler;
    final capped = TextScaler.linear(outer.scale(1).clamp(1.0, 1.2));

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: capped),
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // Background blur
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: SizedBox(height: height),
              ),
              // Translucent surface + subtle border/shadow
              Container(
                height: height,
                decoration: BoxDecoration(
                  color: isDark
                      ? cs.surfaceVariant.withOpacity(0.35)
                      : cs.surfaceVariant.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: cs.outline.withOpacity(isDark ? 0.25 : 0.35),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 16,
                      spreadRadius: 1,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: List.generate(items.length, (i) {
                    return Expanded(
                      child: _NavItem(
                        data: items[i],
                        selected: i == index,
                        selectedColor: selectedColor,
                        unselectedColor: unselectedColor,
                        onTap: () => onSelect(i),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final String label;
  const _NavItemData({required this.icon, required this.label});
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.data,
    required this.selected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  final _NavItemData data;
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? selectedColor : unselectedColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Compute safe internal layout from real available height
          final totalH = constraints.maxHeight;

          // Derive everything from the remaining vertical space so it can never overflow
          final padV = (totalH * 0.16).clamp(6.0, 12.0);
          final usableH = (totalH - padV * 2).clamp(30.0, 200.0);

          // Share space among icon / gap / label
          final labelH = (usableH * 0.30).clamp(12.0, 18.0);
          final gap = (usableH * 0.08).clamp(4.0, 8.0);
          final iconSize = (usableH - labelH - gap).clamp(18.0, 36.0);

          final fontSize = (labelH * 0.86).clamp(10.0, 14.0);

          return Padding(
            padding: EdgeInsets.symmetric(vertical: padV, horizontal: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(data.icon, size: iconSize, color: color),
                SizedBox(height: gap),
                SizedBox(
                  height: labelH,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      data.label,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        letterSpacing: .1,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
