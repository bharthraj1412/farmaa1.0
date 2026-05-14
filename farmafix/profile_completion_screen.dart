import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';

/// Mandatory profile completion screen for new users after Google Sign-In.
class ProfileCompletionScreen extends ConsumerStatefulWidget {
  const ProfileCompletionScreen({super.key});

  @override
  ConsumerState<ProfileCompletionScreen> createState() =>
      _ProfileCompletionScreenState();
}

class _ProfileCompletionScreenState
    extends ConsumerState<ProfileCompletionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _districtCtrl = TextEditingController();
  final _postalCodeCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();

  // FIX: role is now user-selectable at profile completion
  String _selectedRole = 'buyer';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    if (user != null && user.name.isNotEmpty && user.name != 'User') {
      _nameCtrl.text = user.name;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _districtCtrl.dispose();
    _postalCodeCtrl.dispose();
    _addressCtrl.dispose();
    _companyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(authProvider.notifier).completeProfile(
            name: _nameCtrl.text.trim(),
            mobileNumber: _mobileCtrl.text.trim(),
            district: _districtCtrl.text.trim(),
            postalCode: _postalCodeCtrl.text.trim(),
            address: _addressCtrl.text.trim(),
            companyName: _companyCtrl.text.trim().isNotEmpty
                ? _companyCtrl.text.trim()
                : null,
            role: _selectedRole,   // FIX: pass chosen role
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceCream,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                // ── Header ──
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_add_rounded,
                        color: Colors.white, size: 32),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Complete Your Profile',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Fill in your details to get started with Farmaa',
                    style: GoogleFonts.nunito(
                        fontSize: 14, color: AppTheme.textMedium),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 28),

                // ── Role Selection (FIX) ──────────────────────────────────
                _sectionLabel('I am a...'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _roleCard(
                      role: 'farmer',
                      emoji: '🌾',
                      title: 'Farmer',
                      subtitle: 'List & sell my crops',
                    ),
                    const SizedBox(width: 12),
                    _roleCard(
                      role: 'buyer',
                      emoji: '🛒',
                      title: 'Buyer',
                      subtitle: 'Browse & order grains',
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Personal Details ──
                _sectionLabel('Personal Details'),
                const SizedBox(height: 12),
                _buildCard([
                  _buildField(
                    controller: _nameCtrl,
                    label: 'Full Name *',
                    icon: Icons.person_outline,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Name is required';
                      if (v.trim().length > 100) return 'Name must be under 100 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    controller: _mobileCtrl,
                    label: 'Mobile Number *',
                    icon: Icons.phone_outlined,
                    hint: '+91 XXXXXXXXXX',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d+\s\-]')),
                      LengthLimitingTextInputFormatter(15),
                    ],
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Mobile number is required';
                      final cleaned = v.trim().replaceAll(RegExp(r'[\s\-]'), '');
                      String digits = cleaned;
                      if (digits.startsWith('+91')) digits = digits.substring(3);
                      else if (digits.startsWith('91') && digits.length == 12) {
                        digits = digits.substring(2);
                      }
                      if (!RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
                        return 'Enter a valid 10-digit Indian mobile number';
                      }
                      return null;
                    },
                  ),
                ]),
                const SizedBox(height: 24),

                // ── Location Details ──
                _sectionLabel('Location Details'),
                const SizedBox(height: 12),
                _buildCard([
                  _buildField(
                    controller: _districtCtrl,
                    label: 'District *',
                    icon: Icons.map_outlined,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'District is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    controller: _postalCodeCtrl,
                    label: 'Postal Code (PIN) *',
                    icon: Icons.pin_drop_outlined,
                    hint: '6-digit PIN code',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Postal code is required';
                      if (!RegExp(r'^[1-9]\d{5}$').hasMatch(v.trim())) {
                        return 'Enter a valid 6-digit PIN code';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    controller: _addressCtrl,
                    label: 'Address *',
                    icon: Icons.location_on_outlined,
                    hint: 'Full address with village/town',
                    maxLines: 3,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Address is required';
                      if (v.trim().length < 5) return 'Address is too short';
                      return null;
                    },
                  ),
                ]),
                const SizedBox(height: 24),

                // ── Optional ──
                _sectionLabel('Optional'),
                const SizedBox(height: 12),
                _buildCard([
                  _buildField(
                    controller: _companyCtrl,
                    label: 'Company / Organization',
                    icon: Icons.business_outlined,
                    hint: 'If applicable',
                  ),
                ]),
                const SizedBox(height: 32),

                // ── Submit Button ──
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppTheme.primaryGreen.withValues(alpha: 0.6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26)),
                      elevation: 2,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'Complete Profile',
                            style: GoogleFonts.poppins(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Role Card ─────────────────────────────────────────────────────────────
  Widget _roleCard({
    required String role,
    required String emoji,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _selectedRole == role;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedRole = role),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryGreen : Colors.white,
            borderRadius: AppTheme.radiusLarge,
            border: Border.all(
              color: isSelected ? AppTheme.primaryGreen : AppTheme.borderLight,
              width: 2,
            ),
            boxShadow: isSelected ? AppTheme.cardShadow : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: isSelected ? Colors.white : AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.8)
                      : AppTheme.textLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.primaryGreen,
          letterSpacing: 0.5,
        ),
      );

  Widget _buildCard(List<Widget> children) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppTheme.radiusLarge,
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(children: children),
      );

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppTheme.primaryGreen, size: 20),
        filled: true,
        fillColor: AppTheme.surfaceCard,
        border: OutlineInputBorder(
            borderRadius: AppTheme.radiusMedium,
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: AppTheme.radiusMedium,
            borderSide: const BorderSide(
                color: AppTheme.primaryGreen, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: AppTheme.radiusMedium,
            borderSide: const BorderSide(color: AppTheme.errorRed, width: 1)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: AppTheme.radiusMedium,
            borderSide: const BorderSide(color: AppTheme.errorRed, width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
