import 'package:flutter/material.dart';

import 'captcha_challenge_stub.dart'
    if (dart.library.html) 'captcha_challenge_web.dart' as impl;

/// Cross-platform reCAPTCHA v2 checkbox widget.
///
/// - On Web: renders the official Google reCAPTCHA widget via HtmlElementView.
/// - On Mobile: renders via the flutter_easy_recaptcha_v2 package (WebView).
class CaptchaChallenge extends StatelessWidget {
  const CaptchaChallenge({
    super.key,
    required this.siteKey,
    required this.onVerified,
  });

  final String siteKey;
  final void Function(String token) onVerified;

  @override
  Widget build(BuildContext context) {
    return impl.buildCaptcha(
      siteKey: siteKey,
      onVerified: onVerified,
    );
  }
}
