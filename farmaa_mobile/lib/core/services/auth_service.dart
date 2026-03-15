import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api/api_client.dart';
import '../constants/app_constants.dart';
import '../models/user_model.dart';
import 'firebase_auth_service.dart';
import 'google_auth_service.dart';

/// Handles all authentication operations: Firebase email/password, token storage.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final _dio = ApiClient().dio;
  static const _storage = FlutterSecureStorage();
  static SharedPreferences? _prefs;

  Future<void> _initPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // ── Firebase Email/Password Auth Flow ──────────────────────

  Future<({UserModel user, String token})> register({
    required String name,
    required String email,
    required String password,
  }) async {
    // 1. Create user in Firebase Auth
    await FirebaseAuthService.instance.register(
      email: email,
      password: password,
    );

    // 2. Get Firebase ID token
    final idToken = await FirebaseAuthService.instance.getIdToken();
    if (idToken == null) {
      throw Exception('Failed to get Firebase token after registration');
    }

    // 3. Sync user with backend
    final response = await _dio.post('/auth/firebase', data: {
      'firebase_id_token': idToken,
      'name': name,
      'email': email,
    });

    final data = response.data as Map<String, dynamic>;
    final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);

    await _persistSession(token: idToken, user: user);
    return (user: user, token: idToken);
  }

  Future<({UserModel user, String token})> login({
    required String email,
    required String password,
  }) async {
    // 1. Sign in with Firebase Auth
    await FirebaseAuthService.instance.login(
      email: email,
      password: password,
    );

    // 2. Get Firebase ID token
    final idToken = await FirebaseAuthService.instance.getIdToken();
    if (idToken == null) {
      throw Exception('Failed to get Firebase token after login');
    }

    // 3. Sync with backend to get user profile
    final response = await _dio.post('/auth/firebase', data: {
      'firebase_id_token': idToken,
      'email': email,
    });

    final data = response.data as Map<String, dynamic>;
    final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);

    await _persistSession(token: idToken, user: user);
    return (user: user, token: idToken);
  }

  // ── Password Reset ────────────────────────────────────────

  Future<void> sendPasswordResetEmail(String email) async {
    await FirebaseAuthService.instance.sendPasswordResetEmail(email);
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
    // Check Firebase auth state first
    final firebaseUser = fb.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return null;

    // Return persisted user data
    await _initPrefs();
    final raw = _prefs!.getString(AppConstants.userKey);
    if (raw == null) return null;
    try {
      return UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Returns true if a Firebase user is currently signed in.
  Future<bool> isLoggedIn() async {
    return fb.FirebaseAuth.instance.currentUser != null;
  }

  /// Clears all session data and logs the user out.
  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } on DioException {
      // Ignore network errors on logout
    } finally {
      await FirebaseAuthService.instance.signOut();
      await GoogleAuthService.instance.signOut();
      await _storage.deleteAll();
      await _initPrefs();
      await _prefs!.clear();
    }
  }

  // ── Profile ───────────────────────────────────────────────

  /// Fetches the current user's full profile from the server.
  Future<UserModel> getProfile() async {
    final response = await _dio.get('/auth/me');
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
    final response = await _dio.patch('/auth/me', data: {
      'name': name,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (email != null && email.isNotEmpty) 'email': email,
      if (village != null) 'village': village,
      if (district != null) 'district': district,
      if (organization != null) 'org': organization,
    });
    final user = UserModel.fromJson(response.data as Map<String, dynamic>);
    await _initPrefs();
    await _prefs!.setString(
      AppConstants.userKey,
      jsonEncode(user.toJson()),
    );
    return user;
  }


  /// Login with Google Sign-In via Firebase Auth.
  Future<({UserModel user, String token})> loginWithGoogle() async {
    final result = await GoogleAuthService.instance.signIn();

    // Get Firebase ID token after Google sign-in
    final idToken = await FirebaseAuthService.instance.getIdToken();
    if (idToken != null) {
      await _persistSession(token: idToken, user: result.user);
      return (user: result.user, token: idToken);
    }

    await _persistSession(token: result.token, user: result.user);
    return result;
  }
}
