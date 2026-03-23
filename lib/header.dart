import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:nice_rice/theme_controller.dart';

import 'language_controller.dart';       
import 'l10n/app_localizations.dart';     

class PageHeader extends StatefulWidget implements PreferredSizeWidget {
  const PageHeader({
    super.key,
    this.logoScale = 1.4,
    this.logoPadding = const EdgeInsets.symmetric(horizontal: 12),
    this.profileIconSize = 18,
    this.isDarkMode = false,
    this.onThemeChanged,
    this.topBezelPadding = 20,
  });

  final double logoScale;
  final EdgeInsets logoPadding;
  final double profileIconSize;
  final bool isDarkMode;
  final ValueChanged<bool>? onThemeChanged;
  final double topBezelPadding;

  @override
  State<PageHeader> createState() => _PageHeaderState();

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + topBezelPadding);
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

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true)
        .pushNamedAndRemoveUntil('/landing', (r) => false);
  }

  void _openProfilePopup() {
    if (_profilePopup != null) return;

    final overlay = Overlay.of(context)!; 
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
      automaticallyImplyLeading: false,
      backgroundColor:
          theme.appBarTheme.backgroundColor ?? theme.scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: kToolbarHeight + widget.topBezelPadding,
      systemOverlayStyle:
          (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
        statusBarColor:
            theme.appBarTheme.backgroundColor ?? theme.scaffoldBackgroundColor,
      ),
      titleSpacing: 0,
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
                child: Transform.translate(
                  offset: const Offset(0, -4), 
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
              ),
            ],
          ),
        ),
      ),
      actions: [
        SafeArea(
          bottom: false,
          minimum: EdgeInsets.only(top: widget.topBezelPadding),
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
    final BuildContext safeContext =
        Navigator.of(context, rootNavigator: true).overlay!.context;

    widget.onClose();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showEditNameDialog(safeContext);
    });
  }

  void _changePassword() {
    final BuildContext safeContext =
        Navigator.of(context, rootNavigator: true).overlay!.context;

    widget.onClose();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showChangePasswordDialog(safeContext);
    });
  }

  Widget _languageSelector(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final currentCode = LanguageController.instance.locale?.languageCode;

    Widget chip(String label, String? code) {
      final bool selected = currentCode == code || (currentCode == null && code == null);
      return ChoiceChip(
        label: Text(label, style: GoogleFonts.poppins(fontSize: 12.5)),
        selected: selected,
        onSelected: (v) async {
          if (!v) return;
          if (code == null) {
            await LanguageController.instance.setLocale(null);
          } else {
            await LanguageController.instance.setLocale(Locale(code));
          }
          if (mounted) setState(() {});
        },
        selectedColor: context.brand.withOpacity(.18),
        backgroundColor: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: selected ? context.brand : cs.outlineVariant),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.language ?? 'Language',
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withOpacity(.9),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip('System', null),
              chip(t.languageEnglish ?? 'English', 'en'),
              chip(t.languageFilipino ?? 'Filipino', 'fil'),
            ],
          ),
        ],
      ),
    );
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
                    leading: Icon(Icons.password, color: cs.onSurface),
                    title: Text(
                      "Change password",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 13, color: cs.onSurface),
                    ),
                    onTap: _changePassword,
                  ),

                  _languageSelector(context),
                ],

                if (!signedIn) ...[
                  _languageSelector(context),

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

  Future<void> _showEditNameDialog(BuildContext context) async {
    final u = _user;
    if (u == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to edit your name.')),
      );
      return;
    }

    String first = '';
    String last = '';
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
      final data = doc.data();
      first = (data?['firstName'] as String?)?.trim() ?? '';
      last = (data?['lastName'] as String?)?.trim() ?? '';
      if (first.isEmpty && (u.displayName ?? '').trim().isNotEmpty) {
        final parts = u.displayName!.trim().split(' ');
        first = parts.first;
        if (parts.length > 1) {
          last = parts.sublist(1).join(' ');
        }
      }
    } catch (_) {}

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Edit name',
      barrierColor: Colors.black54,
      useRootNavigator: true,
      pageBuilder: (ctx, anim1, anim2) {
        return Center(
          child: _EditNameDialog(
            initialFirst: first,
            initialLast: last,
            brand: context.brand,
            onSaved: (f, l) async {
              final payload = <String, dynamic>{
                'firstName': f,
                'lastName': l,
                'updatedAt': FieldValue.serverTimestamp(),
              };
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(u.uid)
                  .set(payload, SetOptions(merge: true));

              try {
                await u.updateDisplayName(
                    (f.trim() + ' ' + l.trim()).trim());
              } catch (_) {}

              if (mounted) setState(() {});
            },
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return Transform.scale(
          scale: 0.96 + 0.04 * curved.value,
          child: Opacity(opacity: curved.value, child: child),
        );
      },
    );
  }

  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final u = _user;
    if (u == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to change your password.')),
      );
      return;
    }

    final email = u.email;
    if (email == null || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This account does not use an email/password sign-in. Add a password in your account settings.',
          ),
        ),
      );
      return;
    }

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Change password',
      barrierColor: Colors.black54,
      useRootNavigator: true,
      pageBuilder: (ctx, anim1, anim2) {
        return Center(
          child: _ChangePasswordDialog(
            brand: context.brand,
            email: email,
            onChanged: (String currentPw, String newPw) async {
              try {
                final cred = EmailAuthProvider.credential(
                  email: email,
                  password: currentPw,
                );
                await u.reauthenticateWithCredential(cred);
              } on FirebaseAuthException catch (e) {
                String msg;
                switch (e.code) {
                  case 'wrong-password':
                    msg = 'Incorrect current password.';
                    break;
                  case 'too-many-requests':
                    msg = 'Too many attempts. Please try again later.';
                    break;
                  case 'invalid-credential':
                    msg = 'Invalid credential. Please check your password.';
                    break;
                  default:
                    msg = 'Reauthentication failed: ${e.message ?? e.code}';
                }
                throw Exception(msg);
              }

              try {
                await u.updatePassword(newPw);
              } on FirebaseAuthException catch (e) {
                String msg;
                switch (e.code) {
                  case 'weak-password':
                    msg = 'New password is too weak.';
                    break;
                  case 'requires-recent-login':
                    msg = 'Please sign in again and retry.';
                    break;
                  default:
                    msg = 'Failed to update password: ${e.message ?? e.code}';
                }
                throw Exception(msg);
              }
            },
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return Transform.scale(
          scale: 0.96 + 0.04 * curved.value,
          child: Opacity(opacity: curved.value, child: child),
        );
      },
    );
  }
}

// ================= EDIT NAME DIALOG WIDGET =================

class _EditNameDialog extends StatefulWidget {
  const _EditNameDialog({
    required this.initialFirst,
    required this.initialLast,
    required this.brand,
    required this.onSaved,
  });

  final String initialFirst;
  final String initialLast;
  final Color brand;
  final Future<void> Function(String first, String last) onSaved;

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _first = TextEditingController(text: widget.initialFirst);
  late final TextEditingController _last = TextEditingController(text: widget.initialLast);
  bool _saving = false;

  OutlineInputBorder _border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: 2),
      );

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;
    setState(() => _saving = true);
    try {
      await widget.onSaved(_first.text.trim(), _last.text.trim());
      if (mounted) Navigator.of(context, rootNavigator: true).pop(); // close
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name updated.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save name: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brand = widget.brand;

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(blurRadius: 24, color: Colors.black26, offset: Offset(0, 12)),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Edit Name',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Update your first and last name.',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: cs.onSurface.withOpacity(.75),
                  ),
                ),
                const SizedBox(height: 16),
                // First Name
                TextFormField(
                  controller: _first,
                  textInputAction: TextInputAction.next,
                  cursorColor: brand,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    labelText: 'First name',
                    filled: true,
                    fillColor: Colors.white,
                    labelStyle: const TextStyle(color: Colors.black87),
                    hintStyle: const TextStyle(color: Colors.black54),
                    enabledBorder: _border(brand),
                    focusedBorder: _border(brand),
                    errorBorder: _border(Colors.red),
                    focusedErrorBorder: _border(Colors.red),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'First name is required' : null,
                ),
                const SizedBox(height: 12),
                // Last Name
                TextFormField(
                  controller: _last,
                  textInputAction: TextInputAction.done,
                  cursorColor: brand,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    labelText: 'Last name',
                    filled: true,
                    fillColor: Colors.white,
                    labelStyle: const TextStyle(color: Colors.black87),
                    hintStyle: const TextStyle(color: Colors.black54),
                    enabledBorder: _border(brand),
                    focusedBorder: _border(brand),
                    errorBorder: _border(Colors.red),
                    focusedErrorBorder: _border(Colors.red),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context, rootNavigator: true).pop(),
                      child: Text('Cancel',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: brand,
                          )),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _saving ? null : _confirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: _saving
                          ? SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text('Confirm',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ================= CHANGE PASSWORD DIALOG WIDGET =================

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({
    required this.brand,
    required this.email,
    required this.onChanged,
  });

  final Color brand;
  final String email;
  final Future<void> Function(String currentPassword, String newPassword) onChanged;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new1 = TextEditingController();
  final _new2 = TextEditingController();
  bool _saving = false;

  bool _showCurrent = false;
  bool _showNew1 = false;
  bool _showNew2 = false;

  OutlineInputBorder _border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: 2),
      );

  @override
  void dispose() {
    _current.dispose();
    _new1.dispose();
    _new2.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    final currentPw = _current.text;
    final newPw = _new1.text;
    setState(() => _saving = true);
    try {
      await widget.onChanged(currentPw, newPw);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brand = widget.brand;

    InputDecoration _pwdDecoration({
      required String label,
      required bool visible,
      required VoidCallback onToggle,
    }) {
      return InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(color: Colors.black87),
        hintStyle: const TextStyle(color: Colors.black54),
        enabledBorder: _border(brand),
        focusedBorder: _border(brand),
        errorBorder: _border(Colors.red),
        focusedErrorBorder: _border(Colors.red),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        suffixIcon: IconButton(
          icon: Icon(visible ? Icons.visibility : Icons.visibility_off),
          onPressed: onToggle,
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(blurRadius: 24, color: Colors.black26, offset: Offset(0, 12)),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Change Password',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'For security, please enter your current password and a new one.',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: cs.onSurface.withOpacity(.75),
                  ),
                ),
                const SizedBox(height: 16),

                // Current password
                TextFormField(
                  controller: _current,
                  obscureText: !_showCurrent,
                  cursorColor: brand,
                  style: const TextStyle(color: Colors.black),
                  decoration: _pwdDecoration(
                    label: 'Current password',
                    visible: _showCurrent,
                    onToggle: () => setState(() => _showCurrent = !_showCurrent),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter your current password' : null,
                ),
                const SizedBox(height: 12),

                // New password
                TextFormField(
                  controller: _new1,
                  obscureText: !_showNew1,
                  cursorColor: brand,
                  style: const TextStyle(color: Colors.black),
                  decoration: _pwdDecoration(
                    label: 'New password (min 6 chars)',
                    visible: _showNew1,
                    onToggle: () => setState(() => _showNew1 = !_showNew1),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter a new password';
                    if (v.length < 6) return 'At least 6 characters';
                    if (v == _current.text) return 'New password must be different';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Confirm new password
                TextFormField(
                  controller: _new2,
                  obscureText: !_showNew2,
                  cursorColor: brand,
                  style: const TextStyle(color: Colors.black),
                  decoration: _pwdDecoration(
                    label: 'Confirm new password',
                    visible: _showNew2,
                    onToggle: () => setState(() => _showNew2 = !_showNew2),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Confirm your new password';
                    if (v != _new1.text) return 'Passwords do not match';
                    return null;
                  },
                ),

                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context, rootNavigator: true).pop(),
                      child: Text('Cancel',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: brand,
                          )),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _saving ? null : _confirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: _saving
                          ? SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text('Confirm',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
