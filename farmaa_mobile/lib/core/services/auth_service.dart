import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api/api_client.dart';
import '../constants/app_constants.dart';
import '../models/user_model.dart';
import 'google_auth_service.dart';

/// Handles all authentication operations: Google Sign-In, token storage.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _storage = FlutterSecureStorage();
  static SharedPreferences? _prefs;

  Future<void> _initPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // ── Google Sign-In Flow ─────────────────────────────────────

  Future<({UserModel user, String token, bool profileCompleted})> loginWithGoogle() async {
    // 1. Perform Google Sign-In and get Firebase ID token
    final googleResult = await GoogleAuthService.instance.signIn();

    // 2. Exchange with backend via POST /auth/google
    final response = await ApiClient.instance.post('/auth/google', data: {
      'google_id_token': googleResult.idToken,
      'email': googleResult.email,
      'name': googleResult.name,
      'profile_image': googleResult.photoUrl,
    });

    final data = response.data as Map<String, dynamic>;
    final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
    final backendToken = data['access_token'] as String;
    final profileCompleted = data['profile_completed'] as bool? ?? false;

    // 3. Store backend JWT in both secure storage for Dio and prefs
    await ApiClient.instance.saveBackendToken(backendToken);
    await _persistSession(token: backendToken, user: user);

    return (user: user, token: backendToken, profileCompleted: profileCompleted);
  }

  // ── Profile Completion ────────────────────────────────────────

  Future<UserModel> completeProfile({
    required String name,
    required String mobileNumber,
    required String district,
    required String postalCode,
    required String address,
    String? companyName,
  }) async {
    final response = await ApiClient.instance.post('/auth/complete-profile', data: {
      'name': name,
      'mobile_number': mobileNumber,
      'district': district,
      'postal_code': postalCode,
      'address': address,
      if (companyName != null && companyName.isNotEmpty) 'company_name': companyName,
    });

    final user = UserModel.fromJson(response.data as Map<String, dynamic>);
    await _initPrefs();
    await _prefs!.setString(AppConstants.userKey, jsonEncode(user.toJson()));
    return user;
  }

  // ── Session Management ────────────────────────────────────

  Future<void> _persistSession({
    required String token,
    required UserModel user,
  }) async {
    await _initPrefs();
    await Future.wait([
      _storage.write(key: AppConstants.jwtKey, value: token),
      _prefs!.setString(AppConstants.userKey, jsonEncode(user.toJson())),
    ]);
  }

  /// Loads the persisted user from storage, if any.
  Future<UserModel?> getPersistedUser() async {
    await _initPrefs();
    final raw = _prefs!.getString(AppConstants.userKey);
    if (raw == null) return null;
    try {
      return UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Returns true if a user session exists.
  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: AppConstants.jwtKey);
    return token != null && token.isNotEmpty;
  }

  /// Clears all session data and logs the user out.
  Future<void> logout() async {
    try {
      await ApiClient.instance.post('/auth/logout');
    } on DioException {
      // Ignore network errors on logout
    } finally {
      await GoogleAuthService.instance.signOut();
      await _storage.deleteAll();
      await _initPrefs();
      await _prefs!.clear();
    }
  }

  // ── Profile ───────────────────────────────────────────────

  /// Fetches the current user's full profile from the server.
  Future<UserModel> getProfile() async {
    final response = await ApiClient.instance.get('/auth/me');
    return UserModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Updates editable profile fields.
  Future<UserModel> updateProfile({
    required String name,
    String? mobileNumber,
    String? district,
    String? postalCode,
    String? address,
    String? companyName,
  }) async {
    final response = await ApiClient.instance.patch('/auth/me', data: {
      'name': name,
      if (mobileNumber != null && mobileNumber.isNotEmpty) 'mobile_number': mobileNumber,
      if (district != null) 'district': district,
      if (postalCode != null) 'postal_code': postalCode,
      if (address != null) 'address': address,
      if (companyName != null) 'company_name': companyName,
    });
    final user = UserModel.fromJson(response.data as Map<String, dynamic>);
    await _initPrefs();
    await _prefs!.setString(
      AppConstants.userKey,
      jsonEncode(user.toJson()),
    );
    return user;
  }
}
