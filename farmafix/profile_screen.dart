import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/user_model.dart';
import '../../../generated/l10n/app_localizations.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final l = AppLocalizations.of(context);

    if (authState.isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceCream,
        appBar: AppBar(title: Text(l.profile)),
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryGreen),
        ),
      );
    }

    if (user == null) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceCream,
        appBar: AppBar(title: Text(l.profile)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: AppTheme.textLight),
              const SizedBox(height: 16),
              Text('Please login to view your profile',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go(AppRoutes.login),
                child: const Text('Go to Login'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.surfaceCream,
      appBar: AppBar(
        title: Text(l.profile),
        actions: [
          if (user.isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => context.push(AppRoutes.admin),
              tooltip: 'Admin Panel',
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppRoutes.settings),
            tooltip: l.settings,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(authProvider.notifier).refreshProfile(),
        color: AppTheme.primaryGreen,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Avatar
              Container(
                width: 90,
                height: 90,
                decoration: const BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(user.name, style: Theme.of(context).textTheme.headlineSmall),
              Text(user.email ?? '-',
                  style: const TextStyle(color: AppTheme.textMedium)),
              const SizedBox(height: 8),

              // Role badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (user.isFarmer
                      ? AppTheme.primaryGreen
                      : AppTheme.infoBlue).withValues(alpha: 0.1),
                  borderRadius: AppTheme.radiusRound,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(user.isFarmer ? '🌾' : '🛒'),
                    const SizedBox(width: 6),
                    Text(
                      // FIX: show actual role, not hardcoded 'User account'
                      user.role[0].toUpperCase() + user.role.substring(1),
                      style: TextStyle(
                        fontSize: 13,
                        color: user.isFarmer ? AppTheme.primaryGreen : AppTheme.infoBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Verification badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: user.isVerified
                      ? AppTheme.successGreen.withValues(alpha: 0.1)
                      : AppTheme.warningAmber.withValues(alpha: 0.1),
                  borderRadius: AppTheme.radiusRound,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      user.isVerified ? Icons.verified : Icons.pending,
                      size: 14,
                      color: user.isVerified
                          ? AppTheme.successGreen
                          : AppTheme.warningAmber,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      user.isVerified
                          ? l.verifiedAccount
                          : l.verificationPending,
                      style: TextStyle(
                        fontSize: 13,
                        color: user.isVerified
                            ? AppTheme.successGreen
                            : AppTheme.warningAmber,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showEditDialog(context, user, l),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(l.editProfile),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primaryGreen,
                    side: const BorderSide(color: AppTheme.primaryGreen),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Details card
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppTheme.radiusLarge,
                  boxShadow: AppTheme.cardShadow,
                ),
                child: Column(
                  children: [
                    _tile(Icons.person_outline, l.name, user.name),
                    _divider(),
                    _tile(Icons.email_outlined, 'Email', user.email ?? '-'),
                    _divider(),
                    _tile(Icons.phone_outlined, l.phone, user.mobileNumber ?? '-'),
                    _divider(),
                    _tile(Icons.map_outlined, l.district, user.district ?? '-'),
                    _divider(),
                    _tile(Icons.pin_drop_outlined, 'Postal Code', user.postalCode ?? '-'),
                    _divider(),
                    if (user.address != null && user.address!.isNotEmpty) ...[
                      _tile(Icons.location_on_outlined, 'Address', user.address!),
                      _divider(),
                    ],
                    if (user.companyName != null && user.companyName!.isNotEmpty) ...[
                      _tile(Icons.business_outlined, l.organization, user.companyName!),
                      _divider(),
                    ],
                    // FIX: display actual role instead of hardcoded 'User account'
                    _tile(
                      Icons.badge_outlined,
                      l.role,
                      user.isFarmer ? '🌾 Farmer' : '🛒 Buyer',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Tools / Shortcuts
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppTheme.radiusLarge,
                  boxShadow: AppTheme.cardShadow,
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.bar_chart_rounded,
                          color: AppTheme.primaryGreen),
                      title: Text(l.marketPrices),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () => context.push(AppRoutes.farmerPrices),
                    ),
                    _divider(),
                    ListTile(
                      leading: const Icon(Icons.auto_awesome_rounded,
                          color: AppTheme.primaryGreen),
                      title: Text(l.aiAssistant),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () => context.push(AppRoutes.farmerAI),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Logout
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(l.logout),
                        content: Text(l.logoutConfirm),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(dialogContext, false),
                              child: Text(l.cancel)),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.errorRed),
                            child: Text(l.logout),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      await ref.read(authProvider.notifier).logout();
                      if (context.mounted) context.go(AppRoutes.login);
                    }
                  },
                  icon: const Icon(Icons.logout, color: AppTheme.errorRed),
                  label: Text(l.logout,
                      style: const TextStyle(color: AppTheme.errorRed)),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.errorRed)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, UserModel user, AppLocalizations l) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: user.name);
    final mobileCtrl = TextEditingController(text: user.mobileNumber ?? '');
    final districtCtrl = TextEditingController(text: user.district ?? '');
    final postalCodeCtrl = TextEditingController(text: user.postalCode ?? '');
    final addressCtrl = TextEditingController(text: user.address ?? '');
    final companyCtrl = TextEditingController(text: user.companyName ?? '');
    // FIX: allow role switch in edit dialog
    String selectedRole = user.role;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l.editProfile),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: InputDecoration(labelText: l.fullName),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Name is required';
                      if (v.trim().length > 100) return 'Name too long';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: mobileCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: l.phone),
                    validator: (v) {
                      if (v != null && v.trim().isNotEmpty) {
                        final cleaned = v.trim().replaceAll(RegExp(r'[\s-]'), '');
                        String digits = cleaned;
                        if (digits.startsWith('+91')) digits = digits.substring(3);
                        else if (digits.startsWith('91') && digits.length == 12) {
                          digits = digits.substring(2);
                        }
                        if (!RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
                          return 'Invalid Indian mobile number';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: districtCtrl,
                    decoration: InputDecoration(labelText: l.district),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: postalCodeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Postal Code (PIN)'),
                    validator: (v) {
                      if (v != null && v.trim().isNotEmpty) {
                        if (!RegExp(r'^[1-9]\d{5}$').hasMatch(v.trim())) {
                          return 'Enter a valid 6-digit PIN code';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: addressCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Address'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: companyCtrl,
                    decoration: InputDecoration(labelText: l.organization),
                  ),
                  const SizedBox(height: 16),
                  // FIX: role switcher in edit dialog
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(l.role,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textLight)),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final r in ['farmer', 'buyer'])
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: r == 'farmer' ? 6 : 0),
                            child: GestureDetector(
                              onTap: () => setDialogState(() => selectedRole = r),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: selectedRole == r
                                      ? AppTheme.primaryGreen
                                      : AppTheme.surfaceCream,
                                  borderRadius: AppTheme.radiusMedium,
                                  border: Border.all(
                                    color: selectedRole == r
                                        ? AppTheme.primaryGreen
                                        : AppTheme.borderLight,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    r == 'farmer' ? '🌾 Farmer' : '🛒 Buyer',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: selectedRole == r
                                          ? Colors.white
                                          : AppTheme.textDark,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await ref.read(authProvider.notifier).updateProfile(
                        name: nameCtrl.text,
                        mobileNumber:
                            mobileCtrl.text.isNotEmpty ? mobileCtrl.text : null,
                        district:
                            districtCtrl.text.isNotEmpty ? districtCtrl.text : null,
                        postalCode: postalCodeCtrl.text.isNotEmpty
                            ? postalCodeCtrl.text
                            : null,
                        address:
                            addressCtrl.text.isNotEmpty ? addressCtrl.text : null,
                        companyName:
                            companyCtrl.text.isNotEmpty ? companyCtrl.text : null,
                        role: selectedRole,
                      );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(l.profileUpdated),
                          backgroundColor: AppTheme.successGreen),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('${l.updateFailed}: $e'),
                          backgroundColor: AppTheme.errorRed),
                    );
                  }
                }
              },
              child: Text(l.saveChangesBtn),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.primaryGreen),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textLight)),
                  Text(value,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _divider() => const Divider(height: 1, indent: 48);
}
