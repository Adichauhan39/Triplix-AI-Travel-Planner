import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/auth_service.dart';

class AuthGuard extends GetMiddleware {
  AuthGuard({this.requireVerifiedEmail = true});

  final bool requireVerifiedEmail;

  @override
  RouteSettings? redirect(String? route) {
    // Temporary demo account has no real Firebase user, so it skips the
    // Firebase/verification checks below entirely. See AuthService.
    if (AuthService.isDemoSession) return null;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const RouteSettings(name: '/auth', arguments: {'tab': 'login'});
    }

    if (!requireVerifiedEmail) return null;

    final providerIds =
        user.providerData.map((provider) => provider.providerId);
    final isPasswordUser = providerIds.contains('password');

    if (isPasswordUser && !user.emailVerified) {
      return const RouteSettings(name: '/auth', arguments: {'tab': 'login'});
    }

    return null;
  }
}
