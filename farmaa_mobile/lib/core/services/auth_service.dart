import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';
import '../models/user_model.dart';
import 'firebase_auth_service.dart';
import 'google_auth_service.dart';

/// Extracts a clean, user-friendly message from a DioException.
/// Prefers the server's `detail` field, then Dio's own message, then a fallback.
String _parseError(Object e) {
  if (e is DioException) {
    // Prefer server-provided error message
    final data = e.response?.data;
    if (data is Map && data.containsKey('detail')) {
      return data['detail'].toString();
    }
    // Use Dio message if it's clean (not the verbose default)
    final msg = e.message ?? '';
    if (msg.isNotEmpty && !msg.contains('DioException')) {
      return msg;
    }
    // Status-code fallback
    final status = e.response?.statusCode;
    switch (status) {
      case 400: return 'Invalid request. Please check your input.';
      case 401: return 'Invalid credentials. Please try again.';
      case 409: return 'Account already exists with this email or phone.';
      case 422: return 'Validation error. Please check your input.';
      case 500: return 'Server error. Please try again later.';
      default:
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          return 'Connection timed out. Please check your internet.';
        }
        if (e.type == DioExceptionType.connectionError) {
          return 'Cannot connect to server. Please check your internet connection.';
        }
        return 'Something went wrong (code: $status). Please try again.';
    }
  }
  return e.toString().replaceAll('Exception: ', '');
}

/// Handles all authentication operations: direct backend auth, token storage.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  // Create a fresh Dio for each auth request so it always uses the current
  // AppConstants.baseUrl (which may change via discovery or manual config).
  // This instance intentionally has NO auth interceptor to prevent infinite
  // loops (ApiClient's interceptor calls refreshBackendToken → re-enters).
  Dio _createDio() => Dio(BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        contentType: 'application/json',
      ));

  static const _storage = FlutterSecureStorage();

  // ── Direct Backend Auth (email/password — no Firebase dependency) ───────

  Future<({UserModel user, String token})> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      // Call backend /auth/register directly (bcrypt-hashed, no Firebase needed)
      final response = await _createDio().post('/auth/register', data: {
        'name': name,
        'email': email,
        'password': password,
      });

      final data = response.data as Map<String, dynamic>;
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      final backendToken = data['access_token'] as String;
      final refreshToken = data['refresh_token'] as String?;

      await _persistSession(
          token: backendToken, refreshToken: refreshToken, user: user);
      return (user: user, token: backendToken);
    } on DioException catch (e) {
      throw Exception(_parseError(e));
    }
  }

  Future<({UserModel user, String token})> login({
    required String email,
    required String password,
  }) async {
    try {
      // Call backend /auth/login directly (bcrypt-verified, no Firebase needed)
      final response = await _createDio().post('/auth/login', data: {
        'email_or_phone': email,
        'password': password,
      });

      final data = response.data as Map<String, dynamic>;
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      final backendToken = data['access_token'] as String;
      final refreshToken = data['refresh_token'] as String?;

      await _persistSession(
          token: backendToken, refreshToken: refreshToken, user: user);
      return (user: user, token: backendToken);
    } on DioException catch (e) {
      throw Exception(_parseError(e));
    }
  }

  // ── Password Reset ────────────────────────────────────────

  Future<void> sendPasswordResetEmail(String email) async {
    await FirebaseAuthService.instance.sendPasswordResetEmail(email);
  }

  // ── Token Refresh ─────────────────────────────────────────

  /// Refreshes the backend JWT using the stored refresh token.
  /// Falls back to Firebase ID token exchange for Google-auth users.
  Future<String?> refreshBackendToken() async {
    try {
      // 1. Try stored refresh token first (fast path)
      final refreshToken =
          await _storage.read(key: AppConstants.refreshTokenKey);
      if (refreshToken != null) {
        try {
          final response = await _createDio().post(
            '/auth/refresh',
            queryParameters: {'refresh_token': refreshToken},
          );
          final data = response.data as Map<String, dynamic>;
          final newToken = data['access_token'] as String;
          await _storage.write(key: AppConstants.jwtKey, value: newToken);
          return newToken;
        } catch (e) {
          debugPrint('[AuthService] Refresh token exchange failed: $e');
        }
      }

      // 2. Fallback: Firebase token refresh (for Google-auth sessions)
      final firebaseUser = fb.FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        final idToken = await firebaseUser.getIdToken(true);
        if (idToken != null) {
          final response =
              await _createDio().post('/auth/exchange_token', data: {
            'firebase_id_token': idToken,
            'email': firebaseUser.email,
          });
          final data = response.data as Map<String, dynamic>;
          final newToken = data['access_token'] as String;
          final newRefresh = data['refresh_token'] as String?;
          await _storage.write(key: AppConstants.jwtKey, value: newToken);
          if (newRefresh != null) {
            await _storage.write(
                key: AppConstants.refreshTokenKey, value: newRefresh);
          }
          return newToken;
        }
      }

      return null;
    } catch (e) {
      debugPrint('[AuthService] Token refresh failed: $e');
      return null;
    }
  }

  // ── Session Management ────────────────────────────────────

  Future<void> _persistSession({
    required String token,
    String? refreshToken,
    required UserModel user,
  }) async {
    await Future.wait([
      _storage.write(key: AppConstants.jwtKey, value: token),
      _storage.write(
          key: AppConstants.userKey, value: jsonEncode(user.toJson())),
      if (refreshToken != null)
        _storage.write(key: AppConstants.refreshTokenKey, value: refreshToken),
    ]);
  }

  /// Loads the persisted user from secure storage.
  Future<UserModel?> getPersistedUser() async {
    // Check if we have a stored JWT (primary session indicator)
    final jwt = await _storage.read(key: AppConstants.jwtKey);
    if (jwt == null) return null;

    // Return persisted user data from secure storage
    final raw = await _storage.read(key: AppConstants.userKey);
    if (raw == null) return null;
    try {
      return UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Returns true if a session JWT exists.
  Future<bool> isLoggedIn() async {
    final jwt = await _storage.read(key: AppConstants.jwtKey);
    return jwt != null;
  }

  /// Clears all session data and logs the user out.
  Future<void> logout() async {
    try {
      // Try to notify the backend (best-effort)
      final token = await _storage.read(key: AppConstants.jwtKey);
      if (token != null) {
        await _createDio().post(
          '/auth/logout',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
      }
    } on DioException {
      // Ignore network errors on logout
    } finally {
      await FirebaseAuthService.instance.signOut();
      await GoogleAuthService.instance.signOut();
      await _storage.deleteAll();
    }
  }

  // ── Profile ───────────────────────────────────────────────

  /// Helper to get auth options with current JWT.
  Future<Options> _authOptions() async {
    final token = await _storage.read(key: AppConstants.jwtKey);
    return Options(headers: {
      if (token != null) 'Authorization': 'Bearer $token',
    });
  }

  /// Fetches the current user's full profile from the server.
  Future<UserModel> getProfile() async {
    final response =
        await _createDio().get('/auth/me', options: await _authOptions());
    return UserModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Updates editable profile fields.
  Future<UserModel> updateProfile({
    required String name,
    String? phone,
    String? email,
    String? village,
    String? district,
    String? organization,
  }) async {
    final response = await _createDio().patch(
      '/auth/me',
      data: {
        'name': name,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        if (village != null) 'village': village,
        if (district != null) 'district': district,
        if (organization != null) 'org': organization,
      },
      options: await _authOptions(),
    );
    final user = UserModel.fromJson(response.data as Map<String, dynamic>);
    await _storage.write(
      key: AppConstants.userKey,
      value: jsonEncode(user.toJson()),
    );
    return user;
  }

  /// Login with Google Sign-In via Firebase Auth.
  Future<({UserModel user, String token})> loginWithGoogle() async {
    try {
      // 1. Perform Google Sign-In
      final result = await GoogleAuthService.instance.signIn();

      // 2. Get fresh Firebase ID token
      final idToken = await FirebaseAuthService.instance.getIdToken();
      if (idToken == null) {
        throw Exception('Failed to get Firebase token after Google login');
      }

      // 3. Exchange Firebase token for backend JWT
      final response = await _createDio().post('/auth/exchange_token', data: {
        'firebase_id_token': idToken,
        'name': result.user.name,
        'email': result.user.email,
      });

      final data = response.data as Map<String, dynamic>;
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      final backendToken = data['access_token'] as String;
      final refreshToken = data['refresh_token'] as String?;

      await _persistSession(
          token: backendToken, refreshToken: refreshToken, user: user);
      return (user: user, token: backendToken);
    } on DioException catch (e) {
      throw Exception(_parseError(e));
    }
  }
}
