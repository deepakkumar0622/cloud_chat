
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/services/auth_service.dart';
import '../../../../core/services/user_service.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final phoneController = TextEditingController();
  final otpController = TextEditingController();

  final phoneFocus = FocusNode();
  final otpFocus = FocusNode();

  String? verificationId;
  String message = '';

  bool loading = false;
  bool isError = false;

  static const Color background = Color(0xFF101827);
  static const Color surface = Color(0xFF1B2638);
  static const Color accent = Color(0xFF7568F5);
  static const Color secondaryAccent = Color(0xFF478BFF);

  bool get otpSent => verificationId != null;

  void showMessage(String text, {bool error = false}) {
    if (!mounted) return;

    setState(() {
      message = text;
      isError = error;
    });
  }

  Future<void> sendOtp() async {
  final phone = phoneController.text.trim();

  if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone)) {
    showMessage(
      'Enter a valid phone number with country code.',
      error: true,
    );
    return;
  }

  FocusScope.of(context).unfocus();

  setState(() {
    loading = true;
    message = '';
    isError = false;
  });

  try {
    await AuthService.instance.sendOtp(
      phoneNumber: phone,

      onVerificationCompleted: (credential) async {
        await authenticate(credential);
      },

      onVerificationFailed: (error) {
        showMessage(
          error.message ?? error.code,
          error: true,
        );

        if (mounted) {
          setState(() => loading = false);
        }
      },

      onCodeSent: (id, resendToken) {
        if (!mounted) return;

        setState(() {
          verificationId = id;
          loading = false;
          message = 'Verification code sent successfully.';
          isError = false;
        });

        otpFocus.requestFocus();
      },

      onCodeAutoRetrievalTimeout: (id) {
        verificationId = id;
      },
    );
  } catch (e) {
    showMessage(e.toString(), error: true);

    if (mounted) {
      setState(() => loading = false);
    }
  }
}

  Future<void> verifyOtp() async {
  if (verificationId == null) {
    showMessage('Please request an OTP first.', error: true);
    return;
  }

  final otp = otpController.text.trim();

  if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
    showMessage('Please enter the valid 6-digit OTP.', error: true);
    return;
  }

  FocusScope.of(context).unfocus();

  final credential = PhoneAuthProvider.credential(
    verificationId: verificationId!,
    smsCode: otp,
  );

  await authenticate(credential);
}

 Future<void> authenticate(
  PhoneAuthCredential credential,
) async {
  if (!mounted) return;

  setState(() {
    loading = true;
    message = 'Verifying your phone number...';
    isError = false;
  });

  try {
    final result = await AuthService.instance
        .signInWithCredential(credential);

    final user = result.user;

    if (user == null) {
      throw Exception('Authentication failed. Please try again.');
    }

    await UserService.instance.createUserIfNotExists(user);

    if (!mounted) return;

    setState(() {
      message = 'Phone verified successfully!';
      loading = false;
      isError = false;
    });

    // AuthGate automatically handles navigation.
  } on FirebaseAuthException catch (e) {
    showMessage(
      'Authentication error: ${e.message ?? e.code}',
      error: true,
    );

    if (mounted) {
      setState(() => loading = false);
    }
  } catch (e) {
    showMessage(
      'Something went wrong. Please try again.',
      error: true,
    );

    if (mounted) {
      setState(() => loading = false);
    }
  }
}

  void changePhoneNumber() {
    setState(() {
      verificationId = null;
      otpController.clear();
      message = '';
      isError = false;
    });
  }

  @override
  void dispose() {
    phoneController.dispose();
    otpController.dispose();
    phoneFocus.dispose();
    otpFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: [
          // Background decoration
          Positioned(
            top: -120,
            right: -100,
            child: _glowCircle(300, accent.withValues(alpha: 0.13)),
          ),

          Positioned(
            bottom: -150,
            left: -100,
            child: _glowCircle(
              300,
              secondaryAccent.withValues(alpha: 0.10),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 25,
                  vertical: 35,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 15),

                      // Logo
                      _buildLogo(),

                      const SizedBox(height: 25),

                      const Text(
                        'Cloud Chat',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -1,
                        ),
                      ),

                      const SizedBox(height: 9),

                      Text(
                        'Your conversations, connected everywhere.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 14,
                          letterSpacing: 0.2,
                        ),
                      ),

                      const SizedBox(height: 45),

                      // Login Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: surface.withValues(alpha: 0.90),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.07),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 35,
                              offset: const Offset(0, 15),
                            ),
                          ],
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: otpSent
                              ? _buildOtpForm()
                              : _buildPhoneForm(),
                        ),
                      ),

                      const SizedBox(height: 28),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 15,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Secure authentication powered by Firebase',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      Text(
                        'CLOUD CHAT  •  STAY CONNECTED',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.25),
                          fontSize: 10,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 85,
      height: 85,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [accent, secondaryAccent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(27),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.35),
            blurRadius: 25,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(
        Icons.cloud_rounded,
        color: Colors.white,
        size: 48,
      ),
    );
  }

  Widget _buildPhoneForm() {
    return Column(
      key: const ValueKey('phone'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Welcome aboard!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 23,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 9),

        Text(
          'Enter your mobile number to get started with Cloud Chat.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 13,
            height: 1.5,
          ),
        ),

        const SizedBox(height: 30),

        _fieldLabel('Mobile number'),

        const SizedBox(height: 10),

        TextField(
          controller: phoneController,
          focusNode: phoneFocus,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d+]')),
            LengthLimitingTextInputFormatter(16),
          ],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            letterSpacing: 0.5,
          ),
          decoration: _inputDecoration(
            hint: '+91 9876543210',
            icon: Icons.phone_android_rounded,
          ),
          onSubmitted: (_) {
            if (!loading) sendOtp();
          },
        ),

        const SizedBox(height: 24),

        _primaryButton(
          label: 'Continue with phone',
          icon: Icons.arrow_forward_rounded,
          onPressed: sendOtp,
        ),

        const SizedBox(height: 20),

        _statusMessage(),
      ],
    );
  }

  Widget _buildOtpForm() {
    return Column(
      key: const ValueKey('otp'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: loading ? null : changePhoneNumber,
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white70,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 12),
            const Text(
              'Verify your number',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        Text(
          'We sent a 6-digit verification code to',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 13,
          ),
        ),

        const SizedBox(height: 8),

        Row(
          children: [
            Expanded(
              child: Text(
                phoneController.text.trim(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: loading ? null : changePhoneNumber,
              child: const Text(
                'Change',
                style: TextStyle(color: accent),
              ),
            ),
          ],
        ),

        const SizedBox(height: 25),

        _fieldLabel('Verification code'),

        const SizedBox(height: 10),

        TextField(
          controller: otpController,
          focusNode: otpFocus,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 23,
            fontWeight: FontWeight.bold,
            letterSpacing: 12,
          ),
          decoration: _inputDecoration(
            hint: '------',
            icon: Icons.password_rounded,
          ).copyWith(
            counterText: '',
          ),
          onSubmitted: (_) {
            if (!loading) verifyOtp();
          },
        ),

        const SizedBox(height: 25),

        _primaryButton(
          label: 'Verify & Continue',
          icon: Icons.verified_rounded,
          onPressed: verifyOtp,
        ),

        const SizedBox(height: 20),

        _statusMessage(),

        const SizedBox(height: 10),

        Center(
          child: TextButton(
            onPressed: loading ? null : sendOtp,
            child: const Text(
              'Resend verification code',
              style: TextStyle(
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: Colors.white.withValues(alpha: 0.30),
        fontSize: 14,
        letterSpacing: 1,
      ),
      prefixIcon: Icon(
        icon,
        color: accent,
        size: 21,
      ),
      filled: true,
      fillColor: background,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 19,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: 0.07),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: accent,
          width: 1.5,
        ),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [accent, secondaryAccent],
          ),
          borderRadius: BorderRadius.circular(15),
        ),
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white70,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          child: loading
              ? const SizedBox(
                  height: 23,
                  width: 23,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(icon, size: 19),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _statusMessage() {
    if (message.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isError ? Colors.redAccent : Colors.greenAccent)
            .withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? Colors.redAccent : Colors.greenAccent,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError ? Colors.redAccent : Colors.greenAccent,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glowCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color,
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}
