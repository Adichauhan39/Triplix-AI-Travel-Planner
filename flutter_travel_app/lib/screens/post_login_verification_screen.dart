import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PostLoginVerificationScreen extends StatefulWidget {
  const PostLoginVerificationScreen({super.key});

  @override
  State<PostLoginVerificationScreen> createState() =>
      _PostLoginVerificationScreenState();
}

class _PostLoginVerificationScreenState
    extends State<PostLoginVerificationScreen> {
  String get _providerLabel {
    final args = Get.arguments;
    if (args is Map && args['provider'] == 'google') {
      return 'Google';
    }
    return 'Email';
  }

  @override
  void initState() {
    super.initState();
    _startTransition();
  }

  Future<void> _startTransition() async {
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted) {
      Get.offAllNamed('/onboarding');
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
            colors: [
              Colors.blue.shade600,
              Colors.purple.shade600,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.blue.shade50,
                    ),
                    child: Icon(
                      Icons.flight_takeoff,
                      size: 34,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Preparing your journey',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Signed in with $_providerLabel. Taking you to onboarding...',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.blue.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Please wait 3 seconds...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
