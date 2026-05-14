import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

// ── Auth State ────────────────────────────────────────────────────────────────

class AuthState {
  final UserModel? user;
  final bool isLoading;
  final String? error;

  const AuthState({this.user, this.isLoading = false, this.error});

  bool get isAuthenticated => user != null;
  bool get needsProfileCompletion => user != null && !(user!.profileCompleted);

  AuthState copyWith({UserModel? user, bool? isLoading, String? error}) =>
      AuthState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

// ── Auth Notifier ─────────────────────────────────────────────────────────────

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    _loadPersistedUser();
    return const AuthState(isLoading: true);
  }

  Future<void> _loadPersistedUser() async {
    try {
      final user = await AuthService.instance
          .getPersistedUser()
          .timeout(const Duration(seconds: 2));
      state = AuthState(user: user, isLoading: false);
    } catch (e) {
      debugPrint('[AuthNotifier] Session restore failed or timed out: $e');
      state = AuthState(isLoading: false, error: e.toString());
    }
  }

  Future<void> loginWithGoogle() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await AuthService.instance.loginWithGoogle();
      state = AuthState(user: result.user, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  // FIX: added `role` parameter so profile_completion_screen can pass it through
  Future<void> completeProfile({
    required String name,
    required String mobileNumber,
    required String district,
    required String postalCode,
    required String address,
    String? companyName,
    String role = 'buyer',
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await AuthService.instance.completeProfile(
        name: name,
        mobileNumber: mobileNumber,
        district: district,
        postalCode: postalCode,
        address: address,
        companyName: companyName,
        role: role,
      );
      state = AuthState(user: user, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await AuthService.instance.logout().timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('[AuthNotifier] Logout failed or timed out: $e');
    } finally {
      state = const AuthState();
    }
  }

  Future<void> refreshProfile() async {
    try {
      final user = await AuthService.instance.getProfile();
      state = AuthState(user: user, isLoading: false);
    } catch (_) {}
  }

  // FIX: added `role` parameter for role switching
  Future<void> updateProfile({
    required String name,
    String? mobileNumber,
    String? district,
    String? postalCode,
    String? address,
    String? companyName,
    String? role,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final user = await AuthService.instance.updateProfile(
        name: name,
        mobileNumber: mobileNumber,
        district: district,
        postalCode: postalCode,
        address: address,
        companyName: companyName,
        role: role,
      );
      state = AuthState(user: user, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

final splashFinishedProvider = StateProvider<bool>((ref) => false);

final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authProvider).user;
});
