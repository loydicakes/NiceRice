import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/gestures.dart';

// ======= Login Page =======
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  String? _errorText;

  bool get _isFormBasicallyValid {
    final email = _email.text.trim();
    final pass = _password.text;
    return email.isNotEmpty &&
        email.contains('@') &&
        email.contains('.') &&
        pass.length >= 6;
  }

  @override
  void initState() {
    super.initState();
    // ensure no cross-page mirroring
    _email.text = '';
    _password.text = '';
    _email.addListener(() => setState(() {}));
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorText = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Signed in!', style: GoogleFonts.poppins())),
      );

      Navigator.pushNamedAndRemoveUntil(
        context,
        '/main',
        (route) => false,
        arguments: 0, // Home tab
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _errorText = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(FirebaseAuthException e) {
  final code = e.code; // e.g. "invalid-credential", "user-not-found", etc.

  switch (code) {
    case 'invalid-email':
      return 'Please enter a valid email address.';
    case 'user-disabled':
      return 'This account has been disabled.';
    case 'too-many-requests':
      return 'Too many attempts. Please try again later.';
    case 'network-request-failed':
      return 'Network error. Check your connection and try again.';
    // Firebase often uses these generic ones for wrong email/password:
    case 'invalid-credential':
    case 'invalid-login-credentials':
    case 'user-not-found':
    case 'wrong-password':
      return 'Email or password is incorrect.';
    default:
      // Final safety net: never show raw backend text
      return 'Couldn’t sign you in. Please try again.';
  }
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
        SnackBar(
          content: Text(
            'Password reset email sent. Check your inbox.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _errorText = _friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    const themeGreen = Color(0xFF2D4F2B);
    const bgGrey = Color(0xFFF5F5F5);
    const borderGrey = Color(0xFF7C7C7C);

    InputDecoration roundedField({
      required String hint,
      Widget? prefix,
      Widget? suffix,
    }) {
      return InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(color: borderGrey),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        prefixIcon: prefix,
        suffixIcon: suffix,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: borderGrey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: themeGreen, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(30)),
          borderSide: BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(30)),
          borderSide: BorderSide(color: Colors.red, width: 1.5),
        ),
      );
    }

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
              const SizedBox(height: 16),

              Text(
                "Sign in to your account",
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: themeGreen,
                ),
              ),
              const SizedBox(height: 16),

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
                autovalidateMode: AutovalidateMode.disabled, // per-field only
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Email
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      style: GoogleFonts.poppins(),
                      decoration: roundedField(
                        hint: "Email",
                        prefix: const Icon(
                          Icons.email_outlined,
                          color: borderGrey,
                        ),
                      ),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
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
                      decoration: roundedField(
                        hint: "Password",
                        prefix: const Icon(
                          Icons.lock_outline,
                          color: borderGrey,
                        ),
                        suffix: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility,
                            color: borderGrey,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (v) {
                        if (v == null || v.isEmpty)
                          return "Enter your password";
                        if (v.length < 6) return "At least 6 characters";
                        return null;
                      },
                    ),

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
                    const SizedBox(height: 8),

                    // Policies row (login: always checked & disabled)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: true,
                          onChanged: null, // disabled on login
                          activeColor: themeGreen,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        Expanded(
                          child: PoliciesRichText(themeGreen: themeGreen),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Continue Button
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isFormBasicallyValid
                              ? const Color(0xFFA5AB85)
                              : const Color(0xFFD7D7D7),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: _isFormBasicallyValid && !_loading
                            ? _submit
                            : null,
                        child: _loading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "Continue",
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

                    
                    const SizedBox(height: 16),

                    Center(
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.poppins(
                            color: Colors.black87,
                            fontSize: 14,
                          ),
                          children: [
                            const TextSpan(text: "Don’t have an account? "),
                            TextSpan(
                              text: "Sign up here",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2D4F2B), // themeGreen
                                decoration: TextDecoration.underline,
                                decorationThickness: 1.5,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => Navigator.pushReplacementNamed(context, '/signup'),
                            ),
                          ],
                        ),
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

// ======= Shared policies rich text (opens modal) =======
class PoliciesRichText extends StatelessWidget {
  final Color themeGreen;
  const PoliciesRichText({super.key, required this.themeGreen});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.poppins(color: Colors.black87, fontSize: 12),
        children: [
          const TextSpan(text: "I've read and agreed to the "),
          TextSpan(
            text: "User Agreement",
            style: GoogleFonts.poppins(
              color: themeGreen,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
            recognizer: (TapGestureRecognizer()
              ..onTap = () {
                showDialog(
                  context: context,
                  builder: (_) => const PolicyDialog(
                    title: "User Agreement",
                    contentType: PolicyContentType.userAgreement,
                  ),
                );
              }),
          ),
          const TextSpan(text: " and "),
          TextSpan(
            text: "Privacy Policy",
            style: GoogleFonts.poppins(
              color: themeGreen,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
            recognizer: (TapGestureRecognizer()
              ..onTap = () {
                showDialog(
                  context: context,
                  builder: (_) => const PolicyDialog(
                    title: "Privacy Policy",
                    contentType: PolicyContentType.privacyPolicy,
                  ),
                );
              }),
          ),
          const TextSpan(text: "."),
        ],
      ),
    );
  }
}

// ======= Policy Dialog (same content you shared) =======

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
    const themeGreen = Color(0xFF2D4F2B);
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
      return "Welcome to NiceRice. By creating an account or using the app you agree to:\n\n"
          "1) Authorized Use: You may control only devices you own or have been granted access to by the owner.\n"
          "2) Safety: You will follow all safety prompts and confirm you have physical access to the drying chamber when performing risky actions (e.g., calibration, emergency stop).\n"
          "3) Data Storage: Operation logs, alerts, and configuration may be stored to provide history, analytics, diagnostics, and warranty support.\n"
          "4) Notifications: You consent to receive operational alerts (e.g., job complete, fault, at-risk conditions).\n"
          "5) Prohibited Actions: No attempts to bypass security, access other users’ devices, or interfere with sensors/firmware.\n"
          "6) Transfer & Reset: Ownership changes require factory reset or owner approval.\n"
          "7) Updates: Firmware and app updates may be required to ensure reliability and safety.\n"
          "8) Termination: We may suspend access for policy violations or security risks.\n";
    } else {
      return "We respect your privacy. This policy explains how NiceRice handles your data:\n\n"
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