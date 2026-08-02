import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../widgets/triplix_logo.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final AuthService _authService = AuthService();
  final ScrollController _scrollController = ScrollController();
  bool _isGoogleLoading = false;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppConfig.primaryGradient,
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Scrollbar(
                controller: _scrollController,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Container(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    padding: const EdgeInsets.all(AppConfig.paddingLarge),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Logo Section
                        const TriplixLogo(
                          size: 60,
                          padding: EdgeInsets.all(30),
                          backgroundColor: Color(0x33FFFFFF),
                          shape: BoxShape.circle,
                        ),
                        const SizedBox(height: 24),

                        // App Name
                        const Text(
                          'TRIPLIX',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Hero Text
                        const Text(
                          'Your Smart Travel Companion',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w300,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 48),

                        // Login Options
                        Column(
                          children: [
                            // Google Sign In
                            Container(
                              width: double.infinity,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: TextButton.icon(
                                onPressed: _isGoogleLoading
                                    ? null
                                    : _handleGoogleSignIn,
                                icon: _isGoogleLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const FaIcon(
                                        FontAwesomeIcons.google,
                                        color: Color(0xFFDB4437),
                                        size: 20,
                                      ),
                                label: const Text(
                                  'Continue with Google',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Email Sign In
                            Container(
                              width: double.infinity,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                              child: TextButton.icon(
                                onPressed: () => Get.toNamed('/auth',
                                    arguments: {'tab': 'login'}),
                                icon: const Icon(
                                  Icons.email,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                label: const Text(
                                  'Continue with Email',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                        const SizedBox(height: 48),

                        // Terms and Privacy
                        const Text(
                          'By continuing, you agree to our Terms of Service and Privacy Policy',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),

                        // Sign Up Link
                        TextButton(
                          onPressed: () => Get.toNamed('/auth',
                              arguments: {'tab': 'signup'}),
                          child: const Text(
                            'Don\'t have an account? Sign Up',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const SizedBox(height: 40), // Bottom padding
                      ],
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
}
