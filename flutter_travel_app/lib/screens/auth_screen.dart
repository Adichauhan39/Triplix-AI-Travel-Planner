import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../services/recaptcha_service.dart';
import '../widgets/captcha_challenge.dart';
import '../widgets/triplix_logo.dart';

/// Tabs available inside [AuthScreen]. The order here is also the swipe order
/// of the underlying [PageView].
enum AuthTab { login, signup }

/// A single page that combines Login and Sign Up as two swipable cards.
/// The top segmented selector and the [PageView] stay in sync: tapping a
/// segment auto-animates to that card, swiping the card updates the segment.
/// Terms & Privacy is reachable as a draggable bottom sheet from either form.
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    this.initialTab = AuthTab.login,
    this.openTermsOnStart = false,
  });

  final AuthTab initialTab;
  final bool openTermsOnStart;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late AuthTab _selectedTab;

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    _pageController = PageController(initialPage: widget.initialTab.index);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();

    if (widget.openTermsOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showAuthTermsSheet(context);
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _goToTab(AuthTab tab) {
    if (tab == _selectedTab) return;
    _pageController.animateToPage(
      tab.index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int index) {
    final tab = AuthTab.values[index];
    if (tab != _selectedTab) {
      setState(() => _selectedTab = tab);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue.shade600, Colors.purple.shade600],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                const SizedBox(height: 16),
                _Header(selectedTab: _selectedTab),
                const SizedBox(height: 24),
                _AuthTabSelector(
                  selectedTab: _selectedTab,
                  onTabSelected: _goToTab,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: _onPageChanged,
                    children: [
                      _AuthCardWrapper(
                        child: _LoginCard(onSwitchTab: _goToTab),
                      ),
                      _AuthCardWrapper(
                        child: _SignupCard(onSwitchTab: _goToTab),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header (logo + dynamic title)
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.selectedTab});

  final AuthTab selectedTab;

  String get _title {
    switch (selectedTab) {
      case AuthTab.login:
        return 'Welcome Back';
      case AuthTab.signup:
        return 'Create Account';
    }
  }

  String get _subtitle {
    switch (selectedTab) {
      case AuthTab.login:
        return 'Your AI-Powered Travel Agent';
      case AuthTab.signup:
        return 'Start your travel journey';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const TriplixLogo(
          size: 56,
          padding: EdgeInsets.all(16),
          backgroundColor: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            _title,
            key: ValueKey('title-$selectedTab'),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 4),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            _subtitle,
            key: ValueKey('subtitle-$selectedTab'),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Top segmented selector
// ---------------------------------------------------------------------------

class _AuthTabSelector extends StatelessWidget {
  const _AuthTabSelector({
    required this.selectedTab,
    required this.onTabSelected,
  });

  final AuthTab selectedTab;
  final ValueChanged<AuthTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            _segment('Login', AuthTab.login),
            _segment('Sign Up', AuthTab.signup),
          ],
        ),
      ),
    );
  }

  Widget _segment(String label, AuthTab tab) {
    final bool isSelected = tab == selectedTab;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTabSelected(tab),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: isSelected ? Colors.blue.shade700 : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared card wrapper (white rounded panel with scrollable contents)
// ---------------------------------------------------------------------------

class _AuthCardWrapper extends StatelessWidget {
  const _AuthCardWrapper({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Login card
// ---------------------------------------------------------------------------

class _LoginCard extends StatefulWidget {
  const _LoginCard({required this.onSwitchTab});

  final ValueChanged<AuthTab> onSwitchTab;

  @override
  State<_LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends State<_LoginCard>
    with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _rememberMe = false;
  bool _captchaVerified = false;
  bool _captchaServerVerified = false;
  bool _isCaptchaChecking = false;

  bool get _useRealCaptcha => AppConfig.recaptchaSiteKey.trim().isNotEmpty;
  bool get _captchaReady =>
      _useRealCaptcha ? _captchaServerVerified : _captchaVerified;

  Future<void> _openCaptchaChallenge({required String action}) async {
    if (!_useRealCaptcha) return;

    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SizedBox(
          height: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(sheetContext),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Complete the reCAPTCHA challenge to continue.',
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: CaptchaChallenge(
                  siteKey: AppConfig.recaptchaSiteKey,
                  onVerified: (token) async {
                    Navigator.pop(sheetContext);
                    if (!mounted) return;
                    setState(() => _isCaptchaChecking = true);

                    bool verified = false;
                    try {
                      verified = await RecaptchaService.verifyToken(
                        token: token,
                        action: action,
                      );
                    } catch (_) {
                      verified = false;
                    }

                    if (!mounted) return;
                    setState(() {
                      _isCaptchaChecking = false;
                      _captchaServerVerified = verified;
                    });

                    // Use ScaffoldMessenger — Get.snackbar throws
                    // 'No Overlay widget found' on web after the bottom
                    // sheet's context is popped.
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(verified
                              ? 'You are verified. You can continue now.'
                              : 'Could not verify reCAPTCHA token. Please try again.'),
                          backgroundColor: verified ? Colors.green : Colors.red,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _isEmailPasswordUser() {
    final user = _authService.currentUser;
    if (user == null) return false;
    final providerIds =
        user.providerData.map((provider) => provider.providerId);
    return providerIds.contains('password');
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);
    try {
      final user = await _authService.signInWithGoogle();
      if (user != null && mounted) {
        Get.toNamed('/onboarding-loading', arguments: {'provider': 'google'});
      }
    } catch (e) {
      if (!mounted) return;
      Get.snackbar(
        'Sign-In Failed',
        'Could not sign in with Google. Please try again.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  void _showEmailVerificationRequiredDialog(String email) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Verify your email'),
          content: Text(
            'We sent a verification link to $email. Please verify your email before logging in.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await _authService.sendEmailVerification(force: true);
                  if (!mounted) return;
                  Get.snackbar(
                    'Verification email sent',
                    'Please check your inbox and spam folder.',
                    backgroundColor: Colors.green,
                    colorText: Colors.white,
                  );
                } catch (_) {
                  if (!mounted) return;
                  Get.snackbar(
                    'Failed',
                    'Could not send verification email. Try again shortly.',
                    backgroundColor: Colors.red,
                    colorText: Colors.white,
                  );
                }
              },
              child: const Text('Resend email'),
            ),
            ElevatedButton(
              onPressed: () async {
                final verified =
                    await _authService.reloadAndCheckEmailVerified();
                if (!mounted) return;
                if (!verified) {
                  Get.snackbar(
                    'Not verified yet',
                    'Please click the verification link first.',
                    backgroundColor: Colors.orange,
                    colorText: Colors.white,
                  );
                  return;
                }
                Navigator.of(dialogContext).pop();
                Get.toNamed('/onboarding-loading',
                    arguments: {'provider': 'email'});
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600),
              child: const Text('I verified',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
    _passwordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('saved_email');
    final rememberMe = prefs.getBool('remember_me') ?? false;
    if (rememberMe && savedEmail != null && mounted) {
      setState(() {
        _emailController.text = savedEmail;
        _rememberMe = true;
      });
    }
  }

  Future<void> _handleLogin() async {
    // Temporary demo account: skips form validation, captcha, and Firebase
    // entirely so the app can be reviewed without a real inbox to verify.
    // See AuthService.signInWithDemoAccount / AuthGuard.
    if (_authService.matchesDemoCredentials(
      _emailController.text,
      _passwordController.text,
    )) {
      setState(() => _isLoading = true);
      await _authService.signInWithDemoAccount();
      if (!mounted) return;
      setState(() => _isLoading = false);
      Get.toNamed('/onboarding-loading', arguments: {'provider': 'email'});
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    if (!_captchaReady) {
      Get.snackbar(
        'Verify you\'re human',
        _useRealCaptcha
            ? 'Please complete the reCAPTCHA challenge below.'
            : 'Please complete the slide-to-verify check below.',
        backgroundColor: Colors.orange.shade700,
        colorText: Colors.white,
      );
      return;
    }
    setState(() => _isLoading = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      final user = await _authService.signInWithEmail(email, password);
      if (user != null) {
        final isEmailPasswordAccount = _isEmailPasswordUser();
        final emailVerified = await _authService.reloadAndCheckEmailVerified();

        if (isEmailPasswordAccount && !emailVerified) {
          if (mounted) {
            setState(() => _isLoading = false);
            _showEmailVerificationRequiredDialog(email);
          }
          return;
        }

        final prefs = await SharedPreferences.getInstance();
        if (_rememberMe) {
          await prefs.setString('saved_email', email);
          await prefs.setBool('remember_me', true);
        } else {
          await prefs.remove('saved_email');
          await prefs.setBool('remember_me', false);
        }
        if (!mounted) return;
        setState(() => _isLoading = false);
        Get.toNamed(
          '/onboarding-loading',
          arguments: {'provider': 'email'},
        );
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      String message = 'Login failed';
      final msg = e.toString();
      if (msg.contains('user-not-found')) {
        message = 'No account found with this email';
      } else if (msg.contains('wrong-password') ||
          msg.contains('invalid-credential')) {
        message = 'Invalid email or password';
      } else if (msg.contains('too-many-requests')) {
        message = 'Too many attempts. Please try again later';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showForgotPasswordDialog() {
    final resetEmailController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your email and we\'ll send you a password reset link.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: resetEmailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                hintText: 'you@example.com',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = resetEmailController.text.trim();
              if (email.isEmpty || !email.contains('@')) {
                Get.snackbar(
                  'Error',
                  'Please enter a valid email',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
                return;
              }
              try {
                await _authService.sendPasswordReset(email);
                Navigator.pop(context);
                Get.snackbar(
                  'Email Sent',
                  'Check your inbox for the password reset link.',
                  backgroundColor: Colors.green,
                  colorText: Colors.white,
                  duration: const Duration(seconds: 4),
                );
              } catch (_) {
                Get.snackbar(
                  'Error',
                  'Could not send reset email. Check the email address.',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
            ),
            child: const Text(
              'Send Reset Link',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: _fieldDecoration(
              label: 'Email',
              hint: 'demo@triplix.com',
              icon: Icons.email_outlined,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your email';
              }
              if (!value.contains('@')) return 'Please enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: !_isPasswordVisible,
            decoration: _fieldDecoration(
              label: 'Password',
              hint: 'demo123',
              icon: Icons.lock_outline,
              suffix: IconButton(
                icon: Icon(
                  _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(
                  () => _isPasswordVisible = !_isPasswordVisible,
                ),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your password';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: _rememberMe,
                onChanged: (value) =>
                    setState(() => _rememberMe = value ?? false),
              ),
              const Text('Remember me'),
              const Spacer(),
              TextButton(
                onPressed: _showForgotPasswordDialog,
                child: const Text('Forgot Password?'),
              ),
            ],
          ),
          // Progressive reveal: CAPTCHA appears once a password is typed.
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _passwordController.text.length >= 6
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _useRealCaptcha
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _isCaptchaChecking
                                    ? null
                                    : () =>
                                        _openCaptchaChallenge(action: 'login'),
                                icon: _isCaptchaChecking
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : Icon(
                                        _captchaServerVerified
                                            ? Icons.verified
                                            : Icons.security,
                                      ),
                                label: Text(
                                  _captchaServerVerified
                                      ? 'reCAPTCHA verified'
                                      : 'Verify with reCAPTCHA',
                                ),
                              ),
                            ],
                          )
                        : _SlideToVerifyCaptcha(
                            verified: _captchaVerified,
                            onVerified: () =>
                                setState(() => _captchaVerified = true),
                            onReset: () =>
                                setState(() => _captchaVerified = false),
                          ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: (_isLoading || !_captchaReady) ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              disabledBackgroundColor: Colors.blue.shade200,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    _captchaReady
                        ? 'Login'
                        : 'Complete verification to continue',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('or'),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed:
                (_isLoading || _isGoogleLoading) ? null : _handleGoogleSignIn,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: _isGoogleLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const FaIcon(FontAwesomeIcons.google, size: 16),
            label: const Text('Continue with Google'),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "Don't have an account? ",
                style: TextStyle(color: Colors.black54),
              ),
              GestureDetector(
                onTap: () => widget.onSwitchTab(AuthTab.signup),
                child: Text(
                  'Sign Up',
                  style: TextStyle(
                    color: Colors.blue.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Center(
            child: TextButton.icon(
              onPressed: () => showAuthTermsSheet(context),
              icon: Icon(
                Icons.shield_outlined,
                size: 16,
                color: Colors.blue.shade700,
              ),
              label: Text(
                'Terms & Privacy',
                style: TextStyle(color: Colors.blue.shade700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Signup card
// ---------------------------------------------------------------------------

class _SignupCard extends StatefulWidget {
  const _SignupCard({required this.onSwitchTab});

  final ValueChanged<AuthTab> onSwitchTab;

  @override
  State<_SignupCard> createState() => _SignupCardState();
}

class _SignupCardState extends State<_SignupCard>
    with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _acceptedTerms = false;
  bool _captchaVerified = false;
  bool _captchaServerVerified = false;
  bool _isCaptchaChecking = false;

  bool get _useRealCaptcha => AppConfig.recaptchaSiteKey.trim().isNotEmpty;
  bool get _captchaReady =>
      _useRealCaptcha ? _captchaServerVerified : _captchaVerified;

  Future<void> _openCaptchaChallenge({required String action}) async {
    if (!_useRealCaptcha) return;

    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SizedBox(
          height: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(sheetContext),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Complete the reCAPTCHA challenge to continue.',
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: CaptchaChallenge(
                  siteKey: AppConfig.recaptchaSiteKey,
                  onVerified: (token) async {
                    Navigator.pop(sheetContext);
                    if (!mounted) return;
                    setState(() => _isCaptchaChecking = true);

                    bool verified = false;
                    try {
                      verified = await RecaptchaService.verifyToken(
                        token: token,
                        action: action,
                      );
                    } catch (_) {
                      verified = false;
                    }

                    if (!mounted) return;
                    setState(() {
                      _isCaptchaChecking = false;
                      _captchaServerVerified = verified;
                    });

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(verified
                              ? 'You are verified. You can continue now.'
                              : 'Could not verify reCAPTCHA token. Please try again.'),
                          backgroundColor: verified ? Colors.green : Colors.red,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onTextChanged);
    _confirmPasswordController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onTextChanged);
    _confirmPasswordController.removeListener(_onTextChanged);
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _passwordsReady =>
      _passwordController.text.length >= 8 &&
      _passwordController.text == _confirmPasswordController.text;

  String? _validateStrongPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    if (value.length < 8) {
      return 'Use at least 8 characters';
    }
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Include at least one uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Include at least one lowercase letter';
    }
    if (!RegExp(r'\d').hasMatch(value)) {
      return 'Include at least one number';
    }
    if (!RegExp(r'[!@#\$%\^&*(),.?":{}|<>]').hasMatch(value)) {
      return 'Include at least one special character';
    }
    return null;
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);
    try {
      final user = await _authService.signInWithGoogle();
      if (user != null && mounted) {
        await _authService.recordTermsAcceptance();
        Get.toNamed('/onboarding-loading', arguments: {'provider': 'google'});
      }
    } catch (_) {
      if (!mounted) return;
      Get.snackbar(
        'Sign-In Failed',
        'Could not sign in with Google. Please try again.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  String get _signupButtonLabel {
    if (!_passwordsReady) return 'Enter matching passwords';
    if (!_captchaReady) return 'Complete verification';
    if (!_acceptedTerms) return 'Accept Terms to continue';
    return 'Create Account';
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_captchaReady) {
      Get.snackbar(
        'Verify you\'re human',
        _useRealCaptcha
            ? 'Please complete the reCAPTCHA challenge below.'
            : 'Please complete the slide-to-verify check below.',
        backgroundColor: Colors.orange.shade700,
        colorText: Colors.white,
      );
      return;
    }
    if (!_acceptedTerms) {
      Get.snackbar(
        'Terms required',
        'Please accept the Terms & Privacy to continue.',
        backgroundColor: Colors.orange.shade700,
        colorText: Colors.white,
      );
      await showAuthTermsSheet(
        context,
        onAccept: () {
          if (mounted) setState(() => _acceptedTerms = true);
        },
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final user = await _authService.registerWithEmail(
        _emailController.text.trim(),
        _passwordController.text.trim(),
        _nameController.text.trim(),
      );
      if (user != null) {
        await _authService.recordTermsAcceptance();
        await _authService.sendEmailVerification(force: true);
        await _authService.signOut();
        if (!mounted) return;
        setState(() => _isLoading = false);
        widget.onSwitchTab(AuthTab.login);
        Get.snackbar(
          'Account Created',
          'Signup successful. Verify your email, then login to continue.',
          backgroundColor: Colors.green,
          colorText: Colors.white,
          duration: const Duration(seconds: 3),
        );
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      String message = 'Registration failed';
      final msg = e.toString();
      if (msg.contains('email-already-in-use')) {
        message = 'An account already exists with this email';
      } else if (msg.contains('weak-password')) {
        message = 'Password is too weak. Use at least 6 characters';
      } else if (msg.contains('invalid-email')) {
        message = 'Please enter a valid email address';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: _fieldDecoration(
              label: 'Full Name',
              hint: 'John Smith',
              icon: Icons.person_outline,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your name';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: _fieldDecoration(
              label: 'Email',
              hint: 'you@example.com',
              icon: Icons.email_outlined,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your email';
              }
              if (!value.contains('@')) return 'Please enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: !_isPasswordVisible,
            decoration: _fieldDecoration(
              label: 'Password',
              hint: 'At least 8 chars, 1 upper, 1 number, 1 symbol',
              icon: Icons.lock_outline,
              suffix: IconButton(
                icon: Icon(
                  _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(
                  () => _isPasswordVisible = !_isPasswordVisible,
                ),
              ),
            ),
            validator: _validateStrongPassword,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: !_isConfirmPasswordVisible,
            decoration: _fieldDecoration(
              label: 'Confirm Password',
              hint: 'Re-enter your password',
              icon: Icons.lock_outline,
              suffix: IconButton(
                icon: Icon(
                  _isConfirmPasswordVisible
                      ? Icons.visibility_off
                      : Icons.visibility,
                ),
                onPressed: () => setState(
                  () => _isConfirmPasswordVisible = !_isConfirmPasswordVisible,
                ),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please confirm your password';
              }
              if (value != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          // Progressive reveal: CAPTCHA appears after passwords are valid + matching.
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _passwordsReady
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _useRealCaptcha
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _isCaptchaChecking
                                    ? null
                                    : () =>
                                        _openCaptchaChallenge(action: 'signup'),
                                icon: _isCaptchaChecking
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : Icon(
                                        _captchaServerVerified
                                            ? Icons.verified
                                            : Icons.security,
                                      ),
                                label: Text(
                                  _captchaServerVerified
                                      ? 'reCAPTCHA verified'
                                      : 'Verify with reCAPTCHA',
                                ),
                              ),
                            ],
                          )
                        : _SlideToVerifyCaptcha(
                            verified: _captchaVerified,
                            onVerified: () =>
                                setState(() => _captchaVerified = true),
                            onReset: () =>
                                setState(() => _captchaVerified = false),
                          ),
                  )
                : const SizedBox.shrink(),
          ),
          // Progressive reveal: Terms appear once CAPTCHA is verified.
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _captchaReady
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _TermsConsentRow(
                      accepted: _acceptedTerms,
                      onChanged: (value) =>
                          setState(() => _acceptedTerms = value),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: (_isLoading ||
                    !_captchaReady ||
                    !_acceptedTerms ||
                    !_passwordsReady)
                ? null
                : _handleSignup,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              disabledBackgroundColor: Colors.blue.shade200,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    _signupButtonLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('or'),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed:
                (_isLoading || _isGoogleLoading) ? null : _handleGoogleSignIn,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: _isGoogleLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const FaIcon(FontAwesomeIcons.google, size: 16),
            label: const Text('Continue with Google'),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Already have an account? ',
                style: TextStyle(color: Colors.black54),
              ),
              GestureDetector(
                onTap: () => widget.onSwitchTab(AuthTab.login),
                child: Text(
                  'Login',
                  style: TextStyle(
                    color: Colors.blue.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Terms & Conditions bottom sheet
// ---------------------------------------------------------------------------

/// Opens the Terms & Privacy bottom sheet. If [onAccept] is provided, it is
/// invoked when the user taps the "Accept" action (and the sheet is closed).
Future<void> showAuthTermsSheet(
  BuildContext context, {
  VoidCallback? onAccept,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _TermsSheet(onAccept: onAccept),
  );
}

class _TermsSheet extends StatelessWidget {
  const _TermsSheet({this.onAccept});

  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      color: Colors.blue.shade700,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Terms of Service & Privacy Policy',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Last updated: June 2026',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                    for (final section in _termsSections) ...[
                      _TermsSectionTile(section: section),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: Colors.blue.shade600),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Close'),
                        ),
                      ),
                      if (onAccept != null) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              onAccept!.call();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade600,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Accept',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

const List<_TermsSection> _termsSections = <_TermsSection>[
  _TermsSection(
    icon: Icons.verified_user_outlined,
    title: 'Acceptance of Terms',
    body: 'By creating an account or using Triplix, you agree to these Terms '
        'of Service and acknowledge our Privacy Policy. If you do not agree, '
        'please discontinue use of the app.',
  ),
  _TermsSection(
    icon: Icons.travel_explore_outlined,
    title: 'Use of the Service',
    body: 'Triplix provides AI-powered travel recommendations, itineraries '
        'and booking assistance. You are responsible for verifying all '
        'travel details (dates, prices, availability) with the underlying '
        'providers before completing any booking.',
  ),
  _TermsSection(
    icon: Icons.privacy_tip_outlined,
    title: 'Privacy & Data',
    body: 'We collect the data needed to personalise your trip plans '
        '(preferences, search history, account details). Your data is '
        'encrypted in transit and never sold to third parties. You can '
        'request export or deletion at any time from your account.',
  ),
  _TermsSection(
    icon: Icons.payments_outlined,
    title: 'Payments & Refunds',
    body: 'Payments are processed by trusted partners. Cancellation and '
        'refund policies depend on the airline, hotel or operator you '
        'book with. Triplix does not charge hidden fees on top of '
        'partner pricing.',
  ),
  _TermsSection(
    icon: Icons.support_agent_outlined,
    title: 'Support',
    body: 'Reach out via the in-app assistant or support@triplix.app for '
        'help with bookings, account issues or feedback.',
  ),
];

class _TermsSection {
  const _TermsSection({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _TermsSectionTile extends StatelessWidget {
  const _TermsSectionTile({required this.section});

  final _TermsSection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(section.icon, color: Colors.blue.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  section.body,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide-to-verify CAPTCHA (modern, lightweight, no third-party service)
// ---------------------------------------------------------------------------

class _SlideToVerifyCaptcha extends StatefulWidget {
  const _SlideToVerifyCaptcha({
    required this.verified,
    required this.onVerified,
    required this.onReset,
  });

  final bool verified;
  final VoidCallback onVerified;
  final VoidCallback onReset;

  @override
  State<_SlideToVerifyCaptcha> createState() => _SlideToVerifyCaptchaState();
}

class _SlideToVerifyCaptchaState extends State<_SlideToVerifyCaptcha> {
  static const double _thumbSize = 48;
  static const double _trackHeight = 56;
  static const double _padding = 4;

  double _dragX = 0;
  bool _completing = false;

  @override
  Widget build(BuildContext context) {
    if (widget.verified) {
      return _verifiedBanner();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxX = constraints.maxWidth - _thumbSize - (_padding * 2);
        final clampedDrag = _dragX.clamp(0.0, maxX);
        final progress = maxX <= 0 ? 0.0 : clampedDrag / maxX;
        return Container(
          height: _trackHeight,
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(_trackHeight / 2),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Stack(
            children: [
              // Gradient fill that follows the thumb's position.
              AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                curve: Curves.easeOut,
                width: clampedDrag + _thumbSize + (_padding * 2),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade400, Colors.purple.shade300],
                  ),
                  borderRadius: BorderRadius.circular(_trackHeight / 2),
                ),
              ),
              // Hint label, fades out as the user drags.
              Center(
                child: Opacity(
                  opacity: (1 - progress).clamp(0.0, 1.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 18,
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Slide to verify you\'re human',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Draggable thumb.
              Positioned(
                left: clampedDrag + _padding,
                top: _padding,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _dragX = (_dragX + details.delta.dx).clamp(0.0, maxX);
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    if (_dragX >= maxX * 0.92) {
                      _onComplete();
                    } else {
                      setState(() => _dragX = 0);
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      progress >= 0.9 ? Icons.check : Icons.arrow_forward,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _onComplete() async {
    if (_completing) return;
    _completing = true;
    HapticFeedback.mediumImpact();
    widget.onVerified();
  }

  Widget _verifiedBanner() {
    return GestureDetector(
      onLongPress: () {
        // Long-press to reset, in case the user wants to redo the check.
        setState(() {
          _dragX = 0;
          _completing = false;
        });
        widget.onReset();
      },
      child: Container(
        height: _trackHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(_trackHeight / 2),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.green.shade500,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Verified — you\'re human',
                style: TextStyle(
                  color: Colors.green.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              'long-press to redo',
              style: TextStyle(
                color: Colors.green.shade700,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inline Terms & Privacy consent row
// ---------------------------------------------------------------------------

class _TermsConsentRow extends StatelessWidget {
  const _TermsConsentRow({
    required this.accepted,
    required this.onChanged,
  });

  final bool accepted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(!accepted),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: accepted ? Colors.blue.shade600 : Colors.transparent,
                  border: Border.all(
                    color:
                        accepted ? Colors.blue.shade600 : Colors.grey.shade400,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: accepted
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 13,
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(text: 'I agree to the '),
                    TextSpan(
                      text: 'Terms of Service',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => showAuthTermsSheet(
                              context,
                              onAccept: () => onChanged(true),
                            ),
                    ),
                    const TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => showAuthTermsSheet(
                              context,
                              onAccept: () => onChanged(true),
                            ),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared field decoration helper
// ---------------------------------------------------------------------------

InputDecoration _fieldDecoration({
  required String label,
  required String hint,
  required IconData icon,
  Widget? suffix,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: Icon(icon),
    suffixIcon: suffix,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    filled: true,
    fillColor: Colors.grey.shade50,
  );
}
