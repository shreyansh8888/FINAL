import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../navigation/app_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../../auth/screens/privacy_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final lang = ref.watch(languageProvider);
    final pushEnabled = ref.watch(pushNotificationsProvider);
    final emailEnabled = ref.watch(emailNotificationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Appearance
          const _SectionHeader('Appearance'),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Dark Mode'),
            value: isDark,
            onChanged: (_) =>
                ref.read(themeModeProvider.notifier).toggleTheme(),
            activeThumbColor: AppColors.primary,
          ),
          // Language
          const _SectionHeader('Language'),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('App Language'),
            trailing: DropdownButton<String>(
              value: lang,
              underline: const SizedBox.shrink(),
              items: AppConstants.supportedLanguages
                  .map((l) => DropdownMenuItem(
                        value: l['code'],
                        child: Text(l['name']!),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  ref.read(languageProvider.notifier).setLanguage(v);
                }
              },
            ),
          ),
          // Notifications
          const _SectionHeader('Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Push Notifications'),
            subtitle: const Text('Event reminders and updates'),
            value: pushEnabled,
            onChanged: (v) =>
                ref.read(pushNotificationsProvider.notifier).toggle(v),
            activeThumbColor: AppColors.primary,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.email_outlined),
            title: const Text('Email Notifications'),
            subtitle: const Text('Booking confirmations'),
            value: emailEnabled,
            onChanged: (v) =>
                ref.read(emailNotificationsProvider.notifier).toggle(v),
            activeThumbColor: AppColors.primary,
          ),
          // AI Trainer
          const _SectionHeader('AI Trainer'),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('Analysis Frequency'),
            subtitle: const Text('How often frames are analysed'),
            trailing: const Text('500ms',
                style: TextStyle(color: AppColors.primary)),
            onTap: () {},
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: const Text('Voice Feedback'),
            subtitle: const Text('Spoken corrections during training'),
            value: false,
            onChanged: (_) {},
            activeThumbColor: AppColors.primary,
          ),
          // Account
          const _SectionHeader('Account'),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change Password'),
            subtitle: const Text('Sends a reset link to your email'),
            trailing:
                const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () => context.push(AppRoutes.forgotPassword),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing:
                const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PrivacyPolicyScreen(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: const Text('Garba App v${AppConstants.appVersion}'),
            onTap: () {},
          ),
          const Divider(),
          // Danger zone
          const _SectionHeader('Danger Zone'),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.error),
            title: const Text('Delete Account',
                style: TextStyle(color: AppColors.error)),
            onTap: () => _confirmDeleteAccount(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.error),
            title: const Text('Logout',
                style: TextStyle(color: AppColors.error)),
            onTap: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go(AppRoutes.login);
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAccount(
      BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text(
          'This will permanently delete your account and all associated data. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!context.mounted) return;

    // Show a loading indicator while deletion happens
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await ref.read(authProvider.notifier).deleteAccount();
      if (!context.mounted) return;
      Navigator.pop(context); // close loading dialog
      context.go(AppRoutes.login);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}