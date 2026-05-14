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
    // Start with a loading state so the router waits for session restore
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

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await AuthService.instance.register(
        name: name,
        email: email,
        password: password,
      );
      state = AuthState(user: result.user, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await AuthService.instance.login(
        email: email,
        password: password,
      );
      state = AuthState(user: result.user, isLoading: false);
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

  Future<void> updateProfile({
    required String name,
    String? phone,
    String? email,
    String? village,
    String? district,
    String? organization,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final user = await AuthService.instance.updateProfile(
        name: name,
        phone: phone,
        email: email,
        village: village,
        district: district,
        organization: organization,
      );
      state = AuthState(user: user, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
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

  Future<void> sendPasswordResetEmail(String email) async {
    await AuthService.instance.sendPasswordResetEmail(email);
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

/// Signal that the splash animation is complete.
final splashFinishedProvider = StateProvider<bool>((ref) => false);

/// Convenience provider: the current authenticated user (or null).
final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authProvider).user;
});
