import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // Lazy: on web this package asserts a client_id at construction, so only
  // instantiate it on non-web platforms where Google Sign-In is actually used.
  GoogleSignIn? _googleSignInInstance;
  GoogleSignIn get _googleSignIn => _googleSignInInstance ??= GoogleSignIn();
  static const String _termsPolicyVersion = '2026-06';

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign in with email and password
  Future<User?> signInWithEmail(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (credential.user != null) {
      await _saveUserToPrefs(credential.user!);
    }
    return credential.user;
  }

  /// Register with email and password
  Future<User?> registerWithEmail(
      String email, String password, String name) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (credential.user != null) {
      await credential.user!.updateDisplayName(name);
      await credential.user!.reload();
      await _saveUserToPrefs(_auth.currentUser!);
    }
    return _auth.currentUser;
  }

  /// Sign in with Google
  Future<User?> signInWithGoogle() async {
    late final UserCredential userCredential;
    if (kIsWeb) {
      // Web works best with Firebase popup OAuth flow.
      final provider = GoogleAuthProvider();
      provider.addScope('email');
      provider.addScope('profile');
      userCredential = await _auth.signInWithPopup(provider);
    } else {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // User cancelled

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      userCredential = await _auth.signInWithCredential(credential);
    }

    if (userCredential.user != null) {
      await _saveUserToPrefs(userCredential.user!);
    }
    return userCredential.user;
  }

  /// Sign out
  Future<void> signOut() async {
    if (!kIsWeb && _googleSignInInstance != null) {
      await _googleSignIn.signOut();
    }
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', false);
    await prefs.remove('user_email');
    await prefs.remove('user_name');
    await prefs.remove('user_avatar');
  }

  /// Send password reset email
  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  /// Send email verification to currently signed in user.
  Future<void> sendEmailVerification({bool force = false}) async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (!force && user.emailVerified) return;
    await user.sendEmailVerification();
  }

  /// Reload user and return latest verification status.
  Future<bool> reloadAndCheckEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  /// Persist terms acceptance metadata for compliance tracking.
  Future<void> recordTermsAcceptance() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('terms_accepted', true);
    await prefs.setString('terms_policy_version', _termsPolicyVersion);
    await prefs.setString(
        'terms_accepted_at', DateTime.now().toIso8601String());
    await prefs.setString('terms_accepted_uid', _auth.currentUser?.uid ?? '');
  }

  /// Change password (requires current password for reauthentication)
  Future<void> changePassword(
      String currentPassword, String newPassword) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception('No user is signed in');
    }

    // Reauthenticate with current password
    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);

    // Update to new password
    await user.updatePassword(newPassword);
  }

  /// Update user display name
  Future<void> updateDisplayName(String name) async {
    final user = _auth.currentUser;
    if (user != null) {
      await user.updateDisplayName(name);
      await user.reload();
      await _saveUserToPrefs(_auth.currentUser!);
    }
  }

  /// Get Firebase UID for linking bookings
  String? get uid => _auth.currentUser?.uid;

  /// Save user info to SharedPreferences (for app-level usage)
  Future<void> _saveUserToPrefs(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_email', user.email ?? '');
    await prefs.setString('user_name', user.displayName ?? 'User');
    await prefs.setString(
      'user_avatar',
      (user.displayName ?? 'U').substring(0, 1).toUpperCase(),
    );
    await prefs.setBool('is_logged_in', true);
  }
}
