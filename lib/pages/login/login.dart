// lib/pages/login/login.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/gestures.dart'; // 👈 for TapGestureRecognizer

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();

  bool _isLoginMode = true;
  bool _obscure = true;
  bool _loading = false;
  String? _errorText;

  // ✅ New: checkbox state
  bool _acceptedPolicies = false;

  bool get _isFormValid {
    final email = _email.text.trim();
    final pass = _password.text;
    final hasAt = email.contains("@");
    final hasDot = email.contains(".");
    final baseValid = email.isNotEmpty && hasAt && hasDot && pass.length >= 6;

    // ✅ Login no longer gated by the checkbox
    if (_isLoginMode) return baseValid;

    // ✅ Signup still requires acceptance
    return baseValid &&
        _firstName.text.trim().isNotEmpty &&
        _lastName.text.trim().isNotEmpty &&
        _acceptedPolicies;
  }

  @override
  void initState() {
    super.initState();
    // ✅ Returning users on the login screen see it already checked
    _acceptedPolicies = true;

    _email.addListener(() => setState(() {}));
    _password.addListener(() => setState(() {}));
    _firstName.addListener(() => setState(() {}));
    _lastName.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedPolicies) {
      setState(
        () => _errorText =
            "Please accept the User Agreement and Privacy Policy to continue.",
      );
      return;
    }

    setState(() {
      _loading = true;
      _errorText = null;
    });

    try {
      final auth = FirebaseAuth.instance;

      if (_isLoginMode) {
        await auth.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      } else {
        final cred = await auth.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        await _createUserProfile(cred);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isLoginMode ? 'Signed in!' : 'Account created!'),
        ),
      );

      // ✅ Go to AppShell (tabbed app), select Home tab
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/main',
        (route) => false,
        arguments: 0, // 0=Home, 1=Automation, 2=Analytics
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _errorText = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createUserProfile(UserCredential cred) async {
    final user = cred.user;
    if (user == null) return;

    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    final full = [first, last].where((s) => s.isNotEmpty).join(' ');

    final users = FirebaseFirestore.instance.collection('users');

    await users.doc(user.uid).set({
      'uid': user.uid,
      'email': user.email,
      'firstName': first,
      'lastName': last,
      'fullName': full,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'acceptedPoliciesAt':
          FieldValue.serverTimestamp(), // 👈 record acceptance server-side
    }, SetOptions(merge: true));
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _errorText = 'Enter your email to reset your password.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent. Check your inbox.'),
        ),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _errorText = _friendlyError(e));
    }
  }

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email looks invalid.';
      case 'user-disabled':
        return 'This user has been disabled.';
      case 'user-not-found':
        return 'No account found with that email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'weak-password':
        return 'Please choose a stronger password (at least 6 characters).';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return 'Auth error: ${e.message ?? e.code}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeGreen = const Color(0xFF2D4F2B);
    final bgGrey = const Color(0xFFF5F5F5);
    final borderGrey = const Color(0xFF7C7C7C);
    final buttonInactive = const Color(0xFFD7D7D7);
    final buttonActive = const Color(0xFFA5AB85);

    return Scaffold(
      backgroundColor: bgGrey,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                height: 150,
                width: 150,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage("assets/images/1.png"),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                _isLoginMode
                    ? "Sign in to your account"
                    : "Create a new account",
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: themeGreen,
                ),
              ),
              const SizedBox(height: 24),

              if (_errorText != null) ...[
                Text(
                  _errorText!,
                  style: GoogleFonts.poppins(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
              ],

              Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  children: [
                    if (!_isLoginMode) ...[
                      // First name
                      TextFormField(
                        controller: _firstName,
                        textCapitalization: TextCapitalization.words,
                        style: GoogleFonts.poppins(),
                        decoration: InputDecoration(
                          hintText: "First name",
                          hintStyle: GoogleFonts.poppins(color: borderGrey),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          prefixIcon: Icon(
                            Icons.person_outline,
                            color: borderGrey,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide(color: borderGrey),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide(
                              color: themeGreen,
                              width: 1.5,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: const BorderSide(
                              color: Colors.red,
                              width: 1.5,
                            ),
                          ),
                        ),
                        validator: (v) {
                          if (_isLoginMode) return null;
                          if (v == null || v.trim().isEmpty)
                            return 'First name is required';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      // Last name
                      TextFormField(
                        controller: _lastName,
                        textCapitalization: TextCapitalization.words,
                        style: GoogleFonts.poppins(),
                        decoration: InputDecoration(
                          hintText: "Last name",
                          hintStyle: GoogleFonts.poppins(color: borderGrey),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          prefixIcon: Icon(
                            Icons.person_outline,
                            color: borderGrey,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide(color: borderGrey),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide(
                              color: themeGreen,
                              width: 1.5,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: const BorderSide(
                              color: Colors.red,
                              width: 1.5,
                            ),
                          ),
                        ),
                        validator: (v) {
                          if (_isLoginMode) return null;
                          if (v == null || v.trim().isEmpty)
                            return 'Last name is required';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Email
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      style: GoogleFonts.poppins(),
                      decoration: InputDecoration(
                        hintText: "Email",
                        hintStyle: GoogleFonts.poppins(color: borderGrey),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.email_outlined,
                          color: borderGrey,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(color: borderGrey),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(color: themeGreen, width: 1.5),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Colors.red),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(
                            color: Colors.red,
                            width: 1.5,
                          ),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return "Enter your email";
                        if (!v.contains("@") || !v.contains("."))
                          return "Enter a valid email";
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Password
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      style: GoogleFonts.poppins(),
                      decoration: InputDecoration(
                        hintText: "Password",
                        hintStyle: GoogleFonts.poppins(color: borderGrey),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        prefixIcon: Icon(Icons.lock_outline, color: borderGrey),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(color: borderGrey),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(color: themeGreen, width: 1.5),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility,
                            color: borderGrey,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Colors.red),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(
                            color: Colors.red,
                            width: 1.5,
                          ),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty)
                          return "Enter your password";
                        if (v.length < 6)
                          return "Password must be at least 6 characters";
                        return null;
                      },
                    ),

                    if (_isLoginMode)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _loading ? null : _resetPassword,
                          child: Text(
                            'Forgot password?',
                            style: GoogleFonts.poppins(color: themeGreen),
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),

                    // ✅ Agreement row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _isLoginMode
                              ? true
                              : _acceptedPolicies, // ✅ always checked on login
                          onChanged: _isLoginMode
                              ? null // ✅ disabled on login
                              : (v) => setState(
                                  () => _acceptedPolicies = v ?? false,
                                ),
                          activeColor: themeGreen,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),

                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: GoogleFonts.poppins(
                                color: Colors.black87,
                                fontSize: 12,
                              ),
                              children: [
                                const TextSpan(
                                  text: "I've read and agreed to the ",
                                ),
                                TextSpan(
                                  text: "User Agreement",
                                  style: GoogleFonts.poppins(
                                    color: themeGreen,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.underline,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () {
                                      showDialog(
                                        context: context,
                                        builder: (_) => const PolicyDialog(
                                          title: "User Agreement",
                                          contentType:
                                              PolicyContentType.userAgreement,
                                        ),
                                      );
                                    },
                                ),
                                const TextSpan(text: " and "),
                                TextSpan(
                                  text: "Privacy Policy",
                                  style: GoogleFonts.poppins(
                                    color: themeGreen,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.underline,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () {
                                      showDialog(
                                        context: context,
                                        builder: (_) => const PolicyDialog(
                                          title: "Privacy Policy",
                                          contentType:
                                              PolicyContentType.privacyPolicy,
                                        ),
                                      );
                                    },
                                ),
                                const TextSpan(text: "."),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Continue Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isFormValid
                              ? const Color(0xFFA5AB85)
                              : const Color(0xFFD7D7D7),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: _isFormValid && !_loading ? _submit : null,
                        child: _loading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _isLoginMode
                                        ? "Continue"
                                        : "Create account",
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.arrow_forward,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(
                          child: Container(height: 1, color: borderGrey),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            "or",
                            style: GoogleFonts.poppins(color: themeGreen),
                          ),
                        ),
                        Expanded(
                          child: Container(height: 1, color: borderGrey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          /* TODO: Google sign-in */
                        },
                        icon: Image.asset(
                          "assets/images/google.png",
                          height: 20,
                        ),
                        label: Text(
                          "Sign in with Google",
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: themeGreen,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          side: BorderSide(color: borderGrey),
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    RichText(
                      text: TextSpan(
                        text: _isLoginMode
                            ? "Don’t have an account? "
                            : "Already have an account? ",
                        style: GoogleFonts.poppins(color: Colors.black87),
                        children: [
                          WidgetSpan(
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _isLoginMode = !_isLoginMode;
                                // ✅ If we go to login: checked (and disabled). If we go to signup: unchecked.
                                _acceptedPolicies = _isLoginMode ? true : false;
                              }),
                              child: Text(
                                _isLoginMode ? "Sign up here" : "Sign in here",
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  color: themeGreen,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ======= Simple modal dialog for policies =======

enum PolicyContentType { userAgreement, privacyPolicy }

class PolicyDialog extends StatelessWidget {
  final String title;
  final PolicyContentType contentType;
  const PolicyDialog({
    super.key,
    required this.title,
    required this.contentType,
  });

  @override
  Widget build(BuildContext context) {
    final themeGreen = const Color(0xFF2D4F2B);

    return AlertDialog(
      title: Text(
        title,
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Text(
          _contentFor(contentType),
          style: GoogleFonts.poppins(fontSize: 13, height: 1.45),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close', style: GoogleFonts.poppins(color: themeGreen)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: themeGreen,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
          child: Text('OK', style: GoogleFonts.poppins()),
        ),
      ],
    );
  }

  String _contentFor(PolicyContentType type) {
    if (type == PolicyContentType.userAgreement) {
      return
      // Sample User Agreement tailored to NiceRice
      "Welcome to NiceRice. By creating an account or using the app you agree to:\n\n"
          "1) Authorized Use: You may control only devices you own or have been granted access to by the owner.\n"
          "2) Safety: You will follow all safety prompts and confirm you have physical access to the drying chamber when performing risky actions (e.g., calibration, emergency stop).\n"
          "3) Data Storage: Operation logs, alerts, and configuration may be stored to provide history, analytics, diagnostics, and warranty support.\n"
          "4) Notifications: You consent to receive operational alerts (e.g., job complete, fault, at-risk conditions).\n"
          "5) Prohibited Actions: No attempts to bypass security, access other users’ devices, or interfere with sensors/firmware.\n"
          "6) Transfer & Reset: Ownership changes require factory reset or owner approval.\n"
          "7) Updates: Firmware and app updates may be required to ensure reliability and safety.\n"
          "8) Termination: We may suspend access for policy violations or security risks.\n";
    } else {
      return
      // Sample Privacy Policy tailored to NiceRice
      "We respect your privacy. This policy explains how NiceRice handles your data:\n\n"
          "• What we collect: Account info (name, email), device identifiers, sensor readings (temperature, humidity), operational events, and app logs.\n"
          "• Why we collect it: To enable remote control, provide alerts, improve drying efficiency, deliver analytics/history, and offer support/warranty.\n"
          "• Where data is processed: Secure cloud services with role-based access; sensitive operations are logged.\n"
          "• Retention: Operational data may be retained to support long-term analytics and grain preservation goals. You can request deletion of your account data subject to legal/warranty obligations.\n"
          "• Your choices: You can disable certain uploads (may limit analytics), export your data, or delete your account.\n"
          "• Security: We use authentication, encrypted transport, and per-device keys; ownership transfer clears cloud bindings.\n"
          "• Contact: For privacy requests or questions, email support@nicerice.example.\n";
    }
  }
}
