import 'dart:async';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/env_config.dart'; // Contains EnvConfig.baseUrl

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
    // Note: Can inject a dynamic baseUrl if needed, 
    // replacing EnvConfig.baseUrl as per project config
    _dio = Dio(BaseOptions(
      baseUrl: EnvConfig.baseUrl, 
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

  late final Dio _dio;
  
  // Storage layer
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  // Storage Keys
  static const String _tokenKey = 'app_jwt';
  static const String _expiryKey = 'app_jwt_expiry';

  // Concurrency lock for token refreshes
  Future<String?>? _ongoingTokenRefresh;

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

  // ── Authentication & Token Exchange ───────────────────────────────────────

  /// Calls the backend to exchange a Firebase ID token for our native HS256 JWT
  Future<String?> exchangeFirebaseIdToken(String idToken) async {
    try {
      if (kDebugMode) print('[ApiClient] Skipping interceptors to exchange ID token...');
      
      // Perform token exchange WITHOUT our custom interceptors to avoid loops
      final freshDio = Dio(BaseOptions(baseUrl: EnvConfig.baseUrl));
      final user = FirebaseAuth.instance.currentUser;

      final response = await freshDio.post(
        '/auth/exchange_token',
        data: {
          'firebase_id_token': idToken,
          'email': user?.email, // Backend fallback identifier
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data as Map<String, dynamic>;
        final accessJwt = data['access_token'] as String;
        // Default backend emits no explicit expires_in rn, assuming 1h default via prompt
        final expiresInSeconds = data['expires_in'] as int? ?? 3600; 

        await _saveBackendToken(accessJwt, expiresInSeconds);
        return accessJwt;
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('[ApiClient] Token exchange failed: $e');
      return null;
    }
  }

  /// Ensure we have a valid Backend token. If expired, forces a refresh against Firebase -> Backend
  Future<String?> ensureValidBackendToken() async {
    // 1. Thread safety: Block concurrent network refreshes
    if (_ongoingTokenRefresh != null) {
      return await _ongoingTokenRefresh;
    }

    _ongoingTokenRefresh = _forceTokenRefreshOrReturnValid();
    final token = await _ongoingTokenRefresh;
    _ongoingTokenRefresh = null;
    return token;
  }

  Future<String?> _forceTokenRefreshOrReturnValid() async {
    final storedToken = await _storage.read(key: _tokenKey);
    final expiryStr = await _storage.read(key: _expiryKey);

    // 2. Check Expiry
    if (storedToken != null && expiryStr != null) {
      final expirySeconds = int.tryParse(expiryStr) ?? 0;
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      // Buffer of 30 seconds to prevent edge-case race conditions
      if (nowSeconds < (expirySeconds - 30)) {
        return storedToken; // Fast path: Still valid!
      }
    }

    // 3. Fallback: Token is invalid or missing. Attempt to fetch a new Firebase token
    if (kDebugMode) print('[ApiClient] Missing or expired JWT. Fetching fresh Firebase Identity...');
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
       return null; 
    }

    try {
      final freshIdToken = await firebaseUser.getIdToken(true);
      if (freshIdToken == null) return null;

      // 4. Exchange new token at the backend
      return await exchangeFirebaseIdToken(freshIdToken);
    } catch (e) {
       if (kDebugMode) print('[ApiClient] Failed to refresh Firebase token natively: $e');
       return null;
    }
  }

  Future<void> _saveBackendToken(String token, int expiresInSeconds) async {
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expiryEpoch = nowEpoch + expiresInSeconds;

    await Future.wait([
      _storage.write(key: _tokenKey, value: token),
      _storage.write(key: _expiryKey, value: expiryEpoch.toString()),
    ]);
  }

  /// Completely clears the session
  Future<void> clearSession() async {
    if (kDebugMode) print('[ApiClient] Purging secure session...');
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _expiryKey);
  }

  // ── Testing Hooks ─────────────────────────────────────────────────────────

  @visibleForTesting
  Future<void> forceSetJwt(String token, int expiresInSeconds) async {
    await _saveBackendToken(token, expiresInSeconds);
  }
}

// ── Interceptors ────────────────────────────────────────────────────────────

class _AuthInterceptor extends Interceptor {
  final ApiClient _client;
  _AuthInterceptor(this._client);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // 1. Skip paths that inherently don't require auth
    final whiteList = ['/auth/login', '/auth/register', '/auth/firebase', '/auth/exchange_token'];
    if (whiteList.any((path) => options.path.contains(path))) {
      return handler.next(options);
    }

    // 2. Obtain valid token synchronously
    final backendToken = await _client.ensureValidBackendToken();

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
      if (kDebugMode) print('[ApiClient] 401 Unauthorized hit tracking interceptor target');

      // Check if we already retried this exact payload
      if (err.requestOptions.extra['retried'] == true) {
        if (kDebugMode) print('[ApiClient] Rejecting payload. Retry array limit reached.');
        await _client.clearSession(); // Drop token state
        // Return clear app-facing exception
        return handler.next(err.copyWith(error: UnauthorizedException()));
      }

      // Mark request as entering retry phase
      err.requestOptions.extra['retried'] = true;
      
      // Wipe the known bad token so ensureValidBackendToken() forces a full Firebase refresh bypass
      await _client.clearSession(); 

      try {
        final newToken = await _client.ensureValidBackendToken();
        if (newToken != null) {
          if (kDebugMode) print('[ApiClient] Recovery successful. Retrying original request.');
          
          final opts = err.requestOptions;
          opts.headers['Authorization'] = 'Bearer $newToken';
          
          // Retry using the core Dio instance
          final response = await _client._dio.request(
            opts.path,
            data: opts.data,
            queryParameters: opts.queryParameters,
            options: Options(
              method: opts.method,
              headers: opts.headers,
              contentType: opts.contentType,
              responseType: opts.responseType,
              extra: opts.extra,
            ),
          );
          
          return handler.resolve(response);
        } else {
          // Refresh failed
          await _client.clearSession();
          return handler.next(err.copyWith(error: UnauthorizedException()));
        }
      } catch (e) {
        // Recovery loop entirely collapsed
        await _client.clearSession();
        return handler.next(err.copyWith(error: UnauthorizedException()));
      }
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
