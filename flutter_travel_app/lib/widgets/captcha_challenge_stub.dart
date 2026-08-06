import 'package:flutter/material.dart';
import 'package:flutter_easy_recaptcha_v2/flutter_easy_recaptcha_v2.dart';

/// Mobile / non-web implementation using the WebView-based package.
Widget buildCaptcha({
  required String siteKey,
  required void Function(String token) onVerified,
}) {
  return RecaptchaV2(
    apiKey: siteKey,
    onVerifiedSuccessfully: onVerified,
  );
}
