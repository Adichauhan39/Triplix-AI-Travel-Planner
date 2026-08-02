import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../config/app_config.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final AuthService _authService = AuthService();
  String _userName = 'User';
  String _userEmail = '';
  String _userAvatar = 'U';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final user = _authService.currentUser;
    if (user != null) {
      setState(() {
        _userName = user.displayName ?? 'User';
        _userEmail = user.email ?? '';
        _userAvatar = _userName.isNotEmpty
            ? _userName.substring(0, 1).toUpperCase()
            : 'U';
      });
    } else {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _userName = prefs.getString('user_name') ?? 'User';
        _userEmail = prefs.getString('user_email') ?? '';
        _userAvatar = prefs.getString('user_avatar') ?? 'U';
      });
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _userName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Name'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Full Name',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppConfig.primaryColor),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != _userName) {
      setState(() => _isLoading = true);
      try {
        await _authService.updateDisplayName(result);
        await _loadUserInfo();
      } catch (e) {
        Get.snackbar('Error', 'Could not update name',
            backgroundColor: Colors.red, colorText: Colors.white);
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _changePassword() async {
    if (_userEmail.isEmpty) return;

    final currentPwController = TextEditingController();
    final newPwController = TextEditingController();
    final confirmPwController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        bool obscureCurrent = true;
        bool obscureNew = true;
        bool obscureConfirm = true;
        bool isSubmitting = false;

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Change Password'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: currentPwController,
                    obscureText: obscureCurrent,
                    decoration: InputDecoration(
                      labelText: 'Current Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(obscureCurrent
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () => setDialogState(
                            () => obscureCurrent = !obscureCurrent),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: newPwController,
                    obscureText: obscureNew,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      prefixIcon: const Icon(Icons.lock_reset),
                      suffixIcon: IconButton(
                        icon: Icon(obscureNew
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () =>
                            setDialogState(() => obscureNew = !obscureNew),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: confirmPwController,
                    obscureText: obscureConfirm,
                    decoration: InputDecoration(
                      labelText: 'Confirm New Password',
                      prefixIcon: const Icon(Icons.lock_reset),
                      suffixIcon: IconButton(
                        icon: Icon(obscureConfirm
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () => setDialogState(
                            () => obscureConfirm = !obscureConfirm),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final currentPw = currentPwController.text.trim();
                        final newPw = newPwController.text.trim();
                        final confirmPw = confirmPwController.text.trim();

                        if (currentPw.isEmpty ||
                            newPw.isEmpty ||
                            confirmPw.isEmpty) {
                          Get.snackbar('Error', 'All fields are required',
                              backgroundColor: Colors.red,
                              colorText: Colors.white);
                          return;
                        }
                        if (newPw.length < 6) {
                          Get.snackbar('Error',
                              'New password must be at least 6 characters',
                              backgroundColor: Colors.red,
                              colorText: Colors.white);
                          return;
                        }
                        if (newPw != confirmPw) {
                          Get.snackbar('Error', 'New passwords do not match',
                              backgroundColor: Colors.red,
                              colorText: Colors.white);
                          return;
                        }
                        if (currentPw == newPw) {
                          Get.snackbar('Error',
                              'New password must be different from the current password',
                              backgroundColor: Colors.red,
                              colorText: Colors.white);
                          return;
                        }

                        setDialogState(() => isSubmitting = true);
                        try {
                          await _authService.changePassword(currentPw, newPw);
                          Navigator.pop(context);
                          Get.snackbar(
                            'Success',
                            'Password changed successfully!',
                            backgroundColor: Colors.green,
                            colorText: Colors.white,
                            duration: const Duration(seconds: 3),
                          );
                        } catch (e) {
                          setDialogState(() => isSubmitting = false);
                          String message = 'Could not change password';
                          final err = e.toString();
                          if (err.contains('wrong-password') ||
                              err.contains('invalid-credential')) {
                            message = 'Current password is incorrect';
                          } else if (err.contains('weak-password')) {
                            message =
                                'New password is too weak. Use at least 6 characters';
                          } else if (err.contains('requires-recent-login')) {
                            message =
                                'Session expired. Please sign out and sign in again';
                          }
                          Get.snackbar('Error', message,
                              backgroundColor: Colors.red,
                              colorText: Colors.white);
                        }
                      },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.primaryColor),
                child: isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Change Password',
                        style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child:
                const Text('Sign Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _authService.signOut();
      Get.offAllNamed('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Account',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Profile header
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                        gradient: AppConfig.primaryGradient),
                    padding: const EdgeInsets.only(
                        top: 8, bottom: 32, left: 24, right: 24),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 45,
                          backgroundColor: Colors.white,
                          child: Text(
                            _userAvatar,
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: AppConfig.primaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _userName,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _userEmail,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                        if (_authService.uid != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'UID: ${_authService.uid}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Account actions
                  _buildSection('Account', [
                    _buildTile(
                      Icons.person_outline,
                      'Edit Name',
                      subtitle: _userName,
                      onTap: _editName,
                    ),
                    _buildTile(
                      Icons.lock_outline,
                      'Change Password',
                      subtitle: 'Update your password securely',
                      onTap: _changePassword,
                    ),
                    _buildTile(
                      Icons.email_outlined,
                      'Email',
                      subtitle: _userEmail,
                    ),
                  ]),

                  _buildSection('App', [
                    _buildTile(
                      Icons.info_outline,
                      'About',
                      subtitle: 'AI-Powered Travel Planner v1.0',
                    ),
                    _buildTile(
                      Icons.privacy_tip_outlined,
                      'Privacy Policy',
                      onTap: () {},
                    ),
                  ]),

                  const SizedBox(height: 16),

                  // Sign Out button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _signOut,
                        icon: const Icon(Icons.logout, color: Colors.white),
                        label: const Text('Sign Out',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppConfig.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...children,
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildTile(IconData icon, String title,
      {String? subtitle, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: AppConfig.primaryColor),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: const TextStyle(color: AppConfig.textSecondary, fontSize: 12))
          : null,
      trailing: onTap != null
          ? const Icon(Icons.chevron_right, color: Colors.grey)
          : null,
      onTap: onTap,
    );
  }
}
