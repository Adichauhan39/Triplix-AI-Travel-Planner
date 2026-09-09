import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';

import '../config/brand.dart';
import '../services/auth_service.dart';
import '../widgets/aurora_canvas.dart';
import '../widgets/triplix_logo.dart';

/// The first thing anybody sees.
///
/// One mark, one sentence, two ways in. It wears the same ink, teal and sun as
/// the sign-in page behind it, so the app opens in one language and stays in
/// it -- it used to open in a deep-blue gradient and change its mind one tap
/// later.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final ScrollController _scrollController = ScrollController();
  bool _isGoogleLoading = false;

  // The pin rises and settles, slowly, as though it were hanging there.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat(reverse: true);

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);
    try {
      final user = await _authService.signInWithGoogle();
      if (user != null) {
        Get.toNamed(
          '/onboarding-loading',
          arguments: {'provider': 'google'},
        );
      }
    } catch (e) {
      String message = 'Could not sign in with Google. Please try again.';
      final errorText = e.toString();
      if (errorText.contains('popup_closed_by_user')) {
        message = 'Google sign-in popup was closed before completion.';
      } else if (errorText.contains('unauthorized-domain')) {
        message = 'Domain is not authorized in Firebase Auth settings.';
      } else if (errorText.contains('operation-not-allowed')) {
        message = 'Google provider is disabled in Firebase Auth.';
      }
      Get.snackbar(
        'Sign-In Failed',
        message,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.ink,
      body: AuroraCanvas(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Scrollbar(
                controller: _scrollController,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        // Held to a column on a wide screen, like the page
                        // after it.
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FadeInDown(
                                duration: const Duration(milliseconds: 700),
                                child: _pin(),
                              ),
                              const SizedBox(height: 30),
                              FadeIn(
                                delay: const Duration(milliseconds: 150),
                                duration: const Duration(milliseconds: 600),
                                child: _words(),
                              ),
                              const SizedBox(height: 44),
                              FadeInUp(
                                delay: const Duration(milliseconds: 260),
                                duration: const Duration(milliseconds: 650),
                                child: _waysIn(),
                              ),
                              const SizedBox(height: 28),
                              FadeIn(
                                delay: const Duration(milliseconds: 420),
                                duration: const Duration(milliseconds: 600),
                                child: _smallPrint(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _pin() {
    return Center(
      child: AnimatedBuilder(
        animation: _drift,
        builder: (context, child) {
          final lift = Curves.easeInOut.transform(_drift.value) * 8 - 4;
          return Transform.translate(offset: Offset(0, lift), child: child);
        },
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0x14FFFFFF),
            boxShadow: [
              // The pin's own teal, bleeding into the ink behind it.
              BoxShadow(
                color: Color(0x731FA7C4),
                blurRadius: 56,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const TriplixLogo(size: 72, shape: BoxShape.circle),
        ),
      ),
    );
  }

  Widget _words() {
    return Column(
      children: [
        // The name, set as a word rather than shouted in spaced capitals.
        RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 44,
              fontWeight: FontWeight.w700,
              color: Brand.text,
              letterSpacing: -1.2,
              height: 1.0,
            ),
            children: [
              TextSpan(text: 'Triplix'),
              // The sun on the pin, as the full stop.
              TextSpan(text: '.', style: TextStyle(color: Brand.sun)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Real places. Real prices.\nOne plan everyone can edit.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Brand.muted,
            fontSize: 16,
            height: 1.45,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _waysIn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Google first and white: it is the way most people come in, and the
        // one that needs no typing.
        SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _isGoogleLoading ? null : _handleGoogleSignIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Brand.ink,
              disabledBackgroundColor: const Color(0xB3FFFFFF),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            icon: _isGoogleLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const FaIcon(
                    FontAwesomeIcons.google,
                    color: Color(0xFFDB4437),
                    size: 18,
                  ),
            label: const Text(
              'Continue with Google',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 56,
          child: OutlinedButton.icon(
            onPressed: () => Get.toNamed('/auth', arguments: {'tab': 'login'}),
            style: OutlinedButton.styleFrom(
              foregroundColor: Brand.text,
              backgroundColor: Brand.fill,
              side: const BorderSide(color: Brand.hairline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            icon: const Icon(Icons.mail_outline, size: 19, color: Brand.muted),
            label: const Text(
              'Continue with email',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _smallPrint() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'New here? ',
              style: TextStyle(color: Brand.muted, fontSize: 13),
            ),
            GestureDetector(
              onTap: () =>
                  Get.toNamed('/auth', arguments: {'tab': 'signup'}),
              child: const Text(
                'Create an account',
                style: TextStyle(
                  color: Brand.sun,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          'By continuing, you agree to our Terms of Service and Privacy '
          'Policy',
          textAlign: TextAlign.center,
          style: TextStyle(color: Brand.faint, fontSize: 11.5, height: 1.4),
        ),
      ],
    );
  }
}
