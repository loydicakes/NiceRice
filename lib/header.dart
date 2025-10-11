import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:nice_rice/theme_controller.dart';

class PageHeader extends StatefulWidget implements PreferredSizeWidget {
  const PageHeader({
    super.key,
    this.logoScale = 1.4,
    this.logoPadding = const EdgeInsets.symmetric(horizontal: 12),
    this.profileIconSize = 18,
    this.isDarkMode = false,
    this.onThemeChanged,
    this.topBezelPadding = 20, // NEW: add space above the title row
  });

  final double logoScale;
  final EdgeInsets logoPadding;
  final double profileIconSize;
  final bool isDarkMode;
  final ValueChanged<bool>? onThemeChanged;

  /// Extra top padding inside the AppBar (useful for phone bezel/notch).
  final double topBezelPadding;

  @override
  State<PageHeader> createState() => _PageHeaderState();

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + topBezelPadding); // NEW
}

class _PageHeaderState extends State<PageHeader> {
  final LayerLink _profileLink = LayerLink();
  final GlobalKey _profileTargetKey = GlobalKey();
  OverlayEntry? _profilePopup;

  User? get _user => FirebaseAuth.instance.currentUser;

  Future<String?> _fetchFirstName() async {
    final u = _user;
    if (u == null) return null;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
      final data = doc.data();
      final first = (data?['firstName'] as String?)?.trim();
      if (first != null && first.isNotEmpty) return first;
      final dn = (u.displayName ?? '').trim();
      if (dn.isNotEmpty) return dn.split(' ').first;
      final email = u.email;
      if (email != null && email.contains('@')) return email.split('@').first;
    } catch (_) {}
    return null;
  }

  void _toggleProfilePopup() {
    if (_profilePopup == null) {
      _openProfilePopup();
    } else {
      _closeProfilePopup();
    }
  }

  void _closeProfilePopup() {
    _profilePopup?.remove();
    _profilePopup = null;
  }

  void _openProfilePopup() {
    if (_profilePopup != null) return;

    final overlay = Overlay.of(context, rootOverlay: true)!;
    final mq = MediaQuery.of(context);
    final Size screen = mq.size;
    final EdgeInsets viewPadding = mq.viewPadding;

    final RenderBox rb =
        _profileTargetKey.currentContext!.findRenderObject() as RenderBox;
    final Offset anchorTopLeft = rb.localToGlobal(Offset.zero);
    final Size anchorSize = rb.size;
    final double anchorRight = anchorTopLeft.dx + anchorSize.width;

    const double minW = 240.0, maxW = 320.0;
    final double sideGutter = 12.0 + viewPadding.right;
    final double wantedW = (screen.width - sideGutter * 2).clamp(minW, maxW);
    final double maxH = screen.height * 0.80;
    const double vGap = 8.0;

    double left = anchorRight - wantedW;
    double top = anchorTopLeft.dy + anchorSize.height + vGap;

    left = left.clamp(sideGutter, screen.width - sideGutter - wantedW);

    final double safeBottom = screen.height - viewPadding.bottom - 12.0;
    final double safeTop = viewPadding.top + 12.0;
    final double spaceBelow = safeBottom - top;
    final bool willFlipUp = spaceBelow < 220.0;

    _profilePopup = OverlayEntry(
      builder: (_) {
        final double availableHeight = willFlipUp
            ? (top - vGap - safeTop).clamp(160.0, maxH)
            : (safeBottom - top).clamp(160.0, maxH);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleProfilePopup,
              ),
            ),
            Positioned(
              left: left,
              top: willFlipUp ? null : top,
              bottom: willFlipUp ? (screen.height - top) : null,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: minW,
                  maxWidth: wantedW,
                  maxHeight: availableHeight,
                ),
                child: Material(
                  color: Colors.transparent,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(16),
                  child: _ProfilePanel(
                    onClose: _toggleProfilePopup,
                    isDarkMode: widget.isDarkMode,
                    onThemeChanged: widget.onThemeChanged,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_profilePopup!);
  }

  @override
  void dispose() {
    _closeProfilePopup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final width = MediaQuery.of(context).size.width;
    final double logoBox = width < 360 ? 36.0 : (width < 480 ? 38.0 : 42.0);
    final double avatarSize = width < 360 ? 32.0 : 36.0;

    return AppBar(
      backgroundColor:
          theme.appBarTheme.backgroundColor ?? theme.scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,

      // NEW: increase usable height so we can add real top space inside
      toolbarHeight: kToolbarHeight + widget.topBezelPadding,

      systemOverlayStyle:
          (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
        statusBarColor:
            theme.appBarTheme.backgroundColor ?? theme.scaffoldBackgroundColor,
      ),
      titleSpacing: 0,

      // NEW: push the title row down by topBezelPadding without affecting baseline
      title: SafeArea(
        bottom: false,
        minimum: EdgeInsets.only(top: widget.topBezelPadding),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Padding(
                padding: widget.logoPadding,
                child: SizedBox(
                  width: logoBox,
                  height: logoBox,
                  child: Transform.scale(
                    scale: widget.logoScale,
                    child:
                        Image.asset('assets/images/2.png', fit: BoxFit.contain),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'NiceRice',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: context.brand,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

      actions: [
        SafeArea(
          bottom: false,
          minimum: EdgeInsets.only(top: widget.topBezelPadding), // align with title
          child: CompositedTransformTarget(
            key: _profileTargetKey,
            link: _profileLink,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: _toggleProfilePopup,
                borderRadius: BorderRadius.circular(24),
                child: FutureBuilder<String?>(
                  future: _fetchFirstName(),
                  builder: (context, snap) {
                    final bool signedIn = _user != null;
                    final String? photo = _user?.photoURL;
                    return Container(
                      width: avatarSize,
                      height: avatarSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: context.brand, width: 2),
                        image: signedIn && photo != null
                            ? DecorationImage(
                                image: NetworkImage(photo), fit: BoxFit.cover)
                            : null,
                        color: theme.cardColor,
                      ),
                      alignment: Alignment.center,
                      child: signedIn && photo != null
                          ? null
                          : Icon(
                              Icons.person,
                              color: context.brand,
                              size: widget.profileIconSize.clamp(16, 20),
                            ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ================= PROFILE PANEL =================

class _ProfilePanel extends StatefulWidget {
  const _ProfilePanel({
    required this.isDarkMode,
    required this.onThemeChanged,
    required this.onClose,
  });

  final bool isDarkMode;
  final ValueChanged<bool>? onThemeChanged;
  final VoidCallback onClose;

  @override
  State<_ProfilePanel> createState() => _ProfilePanelState();
}

class _ProfilePanelState extends State<_ProfilePanel> {
  User? get _user => FirebaseAuth.instance.currentUser;

  Future<String> _displayName() async {
    final u = _user;
    if (u == null) return "Hello, Farmer!";
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
      final data = doc.data();
      final first = (data?['firstName'] as String?)?.trim();
      if (first != null && first.isNotEmpty) return "Hello, $first!";
      final dn = (u.displayName ?? '').trim();
      if (dn.isNotEmpty) return "Hello, ${dn.split(' ').first}!";
      final email = u.email;
      if (email != null && email.contains('@')) {
        return "Hello, ${email.split('@').first}!";
      }
    } catch (_) {}
    return "Hello!";
  }

  void _goLogin() {
    widget.onClose();
    Navigator.of(context, rootNavigator: true).pushReplacementNamed('/login');
  }

  void _goRegister() {
    widget.onClose();
    Navigator.of(context, rootNavigator: true).pushReplacementNamed('/signup');
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context, rootNavigator: true)
          .pushNamedAndRemoveUntil('/landing', (r) => false);
    }
  }

  void _editPhoto() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Edit photo – TODO')));
  }

  void _editName() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Edit name – TODO')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final signedIn = _user != null;
    final photo = _user?.photoURL;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: cs.surface,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 160),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: signedIn ? _editPhoto : null,
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.cardColor,
                          image: signedIn && photo != null
                              ? DecorationImage(
                                  image: NetworkImage(photo), fit: BoxFit.cover)
                              : null,
                          border: Border.all(color: context.brand, width: 2),
                        ),
                        alignment: Alignment.center,
                        child: signedIn && photo != null
                            ? null
                            : Icon(Icons.person, color: context.brand, size: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FutureBuilder<String>(
                        future: _displayName(),
                        builder: (context, snap) {
                          final text =
                              snap.data ?? (signedIn ? "Hello!" : "Hello, Farmer!");
                          return Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: context.brand,
                            ),
                          );
                        },
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onClose,
                      icon: Icon(Icons.close, size: 20, color: cs.onSurface),
                      tooltip: 'Close',
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                Divider(height: 1, color: cs.outline.withOpacity(.4)),

                if (signedIn) ...[
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(Icons.edit, color: cs.onSurface),
                    title: Text(
                      "Edit name",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 13, color: cs.onSurface),
                    ),
                    onTap: _editName,
                  ),
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(Icons.image_outlined, color: cs.onSurface),
                    title: Text(
                      "Edit photo",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 13, color: cs.onSurface),
                    ),
                    onTap: _editPhoto,
                  ),
                ],

                if (!signedIn) ...[
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(Icons.app_registration, color: cs.onSurface),
                    title: Text(
                      "Register here",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 13, color: cs.onSurface),
                    ),
                    onTap: _goRegister,
                  ),
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(Icons.login, color: cs.onSurface),
                    title: Text(
                      "Sign in for free",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 13, color: cs.onSurface),
                    ),
                    onTap: _goLogin,
                  ),
                ],

                SwitchListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(
                    "Dark mode",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 13, color: cs.onSurface),
                  ),
                  value: widget.isDarkMode,
                  onChanged: (v) {
                    widget.onThemeChanged?.call(v);
                    setState(() {});
                  },
                ),

                Divider(height: 1, color: cs.outline.withOpacity(.4)),

                if (signedIn)
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(Icons.logout, color: cs.onSurface),
                    title: Text(
                      "Log out",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 13, color: cs.onSurface),
                    ),
                    onTap: _logout,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
