import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/environment_config.dart';

/// Clean custom exceptions for the UI to consume
class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException([this.message = 'Session expired. Please sign in again.']);
  @override
  String toString() => message;
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => 'ApiException: $message (Status: $statusCode)';
}

/// A robust Dio-based API client handling backend JWT tokens, secure storage,
/// and automatic 1-time retry workflows for 401 Unauthorized responses.
class ApiClient {
  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: EnvironmentConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ));

    // Register Interceptors
    _dio.interceptors.addAll([
      _AuthInterceptor(this),
      _ErrorInterceptor(),
    ]);
  }

  static final ApiClient instance = ApiClient._internal();
  factory ApiClient() => instance;

  late final Dio _dio;
  Dio get dio => _dio;
  
  // Storage layer
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  // Storage Keys
  static const String _tokenKey = 'app_jwt';
  static const String _expiryKey = 'app_jwt_expiry';

  // ── Public HTTP Methods ───────────────────────────────────────────────────

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters}) {
    return _dio.get<T>(path, queryParameters: queryParameters);
  }

  Future<Response<T>> post<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters}) {
    return _dio.post<T>(path, data: data, queryParameters: queryParameters);
  }

  Future<Response<T>> put<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters}) {
    return _dio.put<T>(path, data: data, queryParameters: queryParameters);
  }

  Future<Response<T>> patch<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters}) {
    return _dio.patch<T>(path, data: data, queryParameters: queryParameters);
  }

  Future<Response<T>> delete<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters}) {
    return _dio.delete<T>(path, data: data, queryParameters: queryParameters);
  }

  Future<Response<T>> request<T>(String path, {
    dynamic data, 
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.request<T>(path, data: data, queryParameters: queryParameters, options: options);
  }

  // ── Token Storage ──────────────────────────────────────────────────────────

  /// Saves a backend JWT token received from /auth/google
  Future<void> saveBackendToken(String token, {int expiresInSeconds = 3600}) async {
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expiryEpoch = nowEpoch + expiresInSeconds;

    await Future.wait([
      _storage.write(key: _tokenKey, value: token),
      _storage.write(key: _expiryKey, value: expiryEpoch.toString()),
    ]);
  }

  /// Gets the stored backend JWT, or null if missing/expired
  Future<String?> getStoredToken() async {
    final storedToken = await _storage.read(key: _tokenKey);
    final expiryStr = await _storage.read(key: _expiryKey);

    if (storedToken == null || expiryStr == null) return null;

    final expirySeconds = int.tryParse(expiryStr) ?? 0;
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Buffer of 30 seconds to prevent edge-case race conditions
    if (nowSeconds < (expirySeconds - 30)) {
      return storedToken; // Still valid
    }

    // Token expired – clear it
    await clearSession();
    return null;
  }

  /// Completely clears the session
  Future<void> clearSession() async {
    if (kDebugMode) print('[ApiClient] Purging secure session...');
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _expiryKey);
  }

  /// Restores a runtime-saved custom backend URL (for local dev testing).
  Future<void> loadPersistedBaseUrl() async {
    final saved = await _storage.read(key: 'farmaa_base_url');
    if (saved != null && saved.isNotEmpty) {
      _dio.options.baseUrl = saved;
    }
  }

  /// Legacy method kept for UI compatibility.
  void resetCircuitBreaker() {}

  // ── Testing Hooks ─────────────────────────────────────────────────────────

  @visibleForTesting
  Future<void> forceSetJwt(String token, int expiresInSeconds) async {
    await saveBackendToken(token, expiresInSeconds: expiresInSeconds);
  }
}

// ── Interceptors ────────────────────────────────────────────────────────────

class _AuthInterceptor extends Interceptor {
  final ApiClient _client;
  _AuthInterceptor(this._client);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // 1. Skip paths that don't require auth (login, public endpoints)
    final whiteList = [
      '/auth/google',
      '/auth/complete-profile',
      '/auth/logout',
      '/crops',              // Public marketplace listing
    ];
    if (whiteList.any((path) => options.path.contains(path))) {
      // Still attach token if available (for /auth/complete-profile which needs it)
      final token = await _client.getStoredToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      return handler.next(options);
    }

    // 2. Get stored token
    final backendToken = await _client.getStoredToken();

    // 3. Log interceptor state
    if (kDebugMode) {
      final hasToken = backendToken != null;
      print('[ApiClient] => ${options.method} ${options.path} | Has Auth: $hasToken');
    }

    // 4. Block request if completely unauthenticated
    if (backendToken == null) {
      return handler.reject(
        DioException(
          requestOptions: options,
          error: UnauthorizedException(),
        )
      );
    }

    // 5. Inject Authorization and Pass
    options.headers['Authorization'] = 'Bearer $backendToken';
    return handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      if (kDebugMode) print('[ApiClient] 401 Unauthorized on ${err.requestOptions.path}');

      // Don't retry auth endpoints – just fail
      if (err.requestOptions.path.contains('/auth/google')) {
        return handler.next(err);
      }

      // Check if we already retried this exact payload
      if (err.requestOptions.extra['retried'] == true) {
        if (kDebugMode) print('[ApiClient] Retry already attempted. Giving up.');
        await _client.clearSession();
        return handler.next(err.copyWith(error: UnauthorizedException()));
      }

      // Mark request as entering retry phase
      err.requestOptions.extra['retried'] = true;
      
      // Wipe the known bad token
      await _client.clearSession();

      // We can't auto-refresh anymore (no exchange_token endpoint)
      // The user needs to re-login via Google
      return handler.next(err.copyWith(error: UnauthorizedException()));
    }

    // Pass along standard non-401 exceptions
    handler.next(err);
  }
}

class _ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.type == DioExceptionType.connectionTimeout || 
        err.type == DioExceptionType.receiveTimeout) {
      handler.next(err.copyWith(error: ApiException('Network timeout. Please check your connection.')));
      return;
    }
    
    // Pass everything generic to the view-model cleanly
    if (err.response?.statusCode != 401 && err.error is! UnauthorizedException) {
      final msg = _extractErrorMessage(err.response);
      handler.next(err.copyWith(error: ApiException(msg, statusCode: err.response?.statusCode)));
      return;
    }
    
    handler.next(err);
  }

  String _extractErrorMessage(dynamic response) {
    if (response?.data is Map) {
      final data = response.data;
      if (data.containsKey('detail')) {
        final detail = data['detail'];
        if (detail is String) return detail;
        if (detail is List && detail.isNotEmpty) return detail[0]['msg'] ?? 'Validation error';
      }
      if (data.containsKey('message')) return data['message'];
    }
    return 'An unexpected error occurred';
  }
}
