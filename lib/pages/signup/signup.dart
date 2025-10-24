import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/gestures.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();

  final _lastName = TextEditingController();
  final _firstName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _acceptedPolicies = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _loading = false;
  String? _errorText;

  bool get _isFormBasicallyValid {
    final email = _email.text.trim();
    return _lastName.text.trim().isNotEmpty &&
        _firstName.text.trim().isNotEmpty &&
        email.contains("@") &&
        email.contains(".") &&
        _password.text.length >= 6 &&
        _confirm.text == _password.text &&
        _acceptedPolicies; 
  }

  @override
  void initState() {
    super.initState();
    for (final c in [_lastName, _firstName, _email, _password, _confirm]) {
      c.text = '';
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _lastName.dispose();
    _firstName.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _showVerificationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Verify Your Email',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('A verification email has been sent to:',
                    style: GoogleFonts.poppins()),
                const SizedBox(height: 8),
                Text(_email.text.trim(),
                    style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Text(
                  'Please click the link in the email to activate your account. You can log in after verifying.',
                  style: GoogleFonts.poppins(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('OK',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2D4F2B))),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushReplacementNamed(context, '/login');
              },
            ),
          ],
        );
      },
    );
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
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );

      final user = cred.user!;
      await user.sendEmailVerification();

      final fullName =
          "${_firstName.text.trim()} ${_lastName.text.trim()}".trim();
      await user.updateDisplayName(fullName);

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': _email.text.trim(),
        'firstName': _firstName.text.trim(),
        'lastName': _lastName.text.trim(),
        'fullName': fullName,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'acceptedPoliciesAt': FieldValue.serverTimestamp(),
        'isSuspended': false,
      }, SetOptions(merge: true));

      if (!mounted) return;
      _showVerificationDialog();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        setState(() =>
            _errorText = 'This email is already registered. Please sign in.');
      } else {
        setState(() => _errorText = 'An error occurred. Please try again.');
      }
    } catch (_) {
      setState(() => _errorText = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const themeGreen = Color(0xFF2D4F2B);
    const bgGrey = Color(0xFFF5F5F5);
    const borderGrey = Color(0xFF7C7C7C);
    const buttonInactive = Color(0xFFD7D7D7);
    const buttonActive = Color(0xFFA5AB85);

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
              Container(
                height: 120,
                width: 120,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage("assets/images/1.png"),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Sign Up",
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
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
                autovalidateMode: AutovalidateMode.disabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _lastName,
                      textCapitalization: TextCapitalization.words,
                      style: GoogleFonts.poppins(),
                      decoration: roundedField(hint: "Last Name"),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? "Required" : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _firstName,
                      textCapitalization: TextCapitalization.words,
                      style: GoogleFonts.poppins(),
                      decoration: roundedField(hint: "First Name"),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? "Required" : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      style: GoogleFonts.poppins(),
                      decoration: roundedField(
                        hint: "Email",
                        prefix:
                            const Icon(Icons.email_outlined, color: borderGrey),
                      ),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (v) {
                        if (v == null || v.isEmpty) return "Enter your email";
                        if (!v.contains("@") || !v.contains("."))
                          return "Enter a valid email";
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure1,
                      style: GoogleFonts.poppins(),
                      decoration: roundedField(
                        hint: "Password",
                        prefix:
                            const Icon(Icons.lock_outline, color: borderGrey),
                        suffix: IconButton(
                          icon: Icon(
                            _obscure1
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: borderGrey,
                          ),
                          onPressed: () =>
                              setState(() => _obscure1 = !_obscure1),
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
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _confirm,
                      obscureText: _obscure2,
                      style: GoogleFonts.poppins(),
                      decoration: roundedField(
                        hint: "Confirm password",
                        prefix:
                            const Icon(Icons.lock_outline, color: borderGrey),
                        suffix: IconButton(
                          icon: Icon(
                            _obscure2
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: borderGrey,
                          ),
                          onPressed: () =>
                              setState(() => _obscure2 = !_obscure2),
                        ),
                      ),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (v) {
                        if (v == null || v.isEmpty)
                          return "Re-type your password";
                        if (v != _password.text)
                          return "Passwords do not match";
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _acceptedPolicies,
                          onChanged: (v) =>
                              setState(() => _acceptedPolicies = v ?? false),
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
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isFormBasicallyValid
                              ? buttonActive
                              : buttonInactive,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed:
                            _isFormBasicallyValid && !_loading ? _submit : null,
                        child: _loading
                            ? const CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2)
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "Create account",
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward,
                                      color: Colors.white),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const SizedBox(height: 16),
                    Center(
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.poppins(
                            color: Colors.black87,
                            fontSize: 14,
                          ),
                          children: [
                            const TextSpan(text: "Already have an account? "),
                            TextSpan(
                              text: "Sign in here",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                color: themeGreen,
                                decoration: TextDecoration.underline,
                                decorationThickness: 1.5,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => Navigator.pushReplacementNamed(
                                      context,
                                      '/login',
                                    ),
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