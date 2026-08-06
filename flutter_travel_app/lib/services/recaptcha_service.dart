import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class RecaptchaService {
  static Future<bool> verifyToken({
    required String token,
    required String action,
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/api/security/verify-captcha');
    debugPrint('[reCAPTCHA] POST $uri (token len=${token.length})');

    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': token,
          'action': action,
        }),
      );

      debugPrint(
          '[reCAPTCHA] Backend responded ${response.statusCode}: ${response.body}');
      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['verified'] == true;
    } catch (e, st) {
      debugPrint('[reCAPTCHA] verifyToken error: $e\n$st');
      return false;
    }
  }
}
