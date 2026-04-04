import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Result from Google Sign-In containing data needed for backend auth.
class GoogleSignInResult {
  final String idToken;
  final String email;
  final String name;
  final String? photoUrl;

  const GoogleSignInResult({
    required this.idToken,
    required this.email,
    required this.name,
    this.photoUrl,
  });
}

/// Handles Google Sign-In flow via Firebase Auth.
///
/// Uses the google_sign_in v7 API:
/// - Singleton via [GoogleSignIn.instance]
/// - Requires [initialize] to be called once before use
/// - Authentication via [authenticate] (replaces old signIn())
/// - User state tracked via [authenticationEvents] stream
class GoogleAuthService {
  GoogleAuthService._();
  static final GoogleAuthService instance = GoogleAuthService._();

  static const _serverClientId =
      '603178299511-c40kmarpdjg1ntjjcebgmnlj7t521dvg.apps.googleusercontent.com';

  bool _initialized = false;
  GoogleSignInAccount? _currentUser;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSubscription;

  /// Must be called once at app startup (e.g., in main() or AuthService.init).
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await GoogleSignIn.instance.initialize(
      serverClientId: _serverClientId,
    );

    // Listen to authentication events to track current user
    _authSubscription = GoogleSignIn.instance.authenticationEvents
        .listen(_handleAuthenticationEvent)
          ..onError(_handleAuthenticationError);

    // Attempt a lightweight (silent) authentication on startup
    unawaited(GoogleSignIn.instance.attemptLightweightAuthentication());
  }

  void _handleAuthenticationEvent(GoogleSignInAuthenticationEvent event) {
    if (event is GoogleSignInAuthenticationEventSignIn) {
      _currentUser = event.user;
      debugPrint('[GoogleAuth] Signed in: ${event.user.email}');
    } else if (event is GoogleSignInAuthenticationEventSignOut) {
      _currentUser = null;
      debugPrint('[GoogleAuth] Signed out');
    }
  }

  void _handleAuthenticationError(Object error) {
    debugPrint('[GoogleAuth] Auth stream error: $error');
    _currentUser = null;
  }

  /// Performs Google Sign-In using [authenticate()], authenticates with
  /// Firebase, and returns the Firebase ID token and user info.
  Future<GoogleSignInResult> signIn() async {
    assert(_initialized,
        'GoogleAuthService.initialize() must be called before signIn()');

    // 1. Trigger Google Sign-In UI (v7: authenticate() replaces signIn())
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw Exception(
          'Google Sign-In interactive flow is not supported on this platform');
    }

    await GoogleSignIn.instance.authenticate();

    // After authenticate(), _currentUser is updated by the authenticationEvents stream.
    final googleUser = _currentUser;
    if (googleUser == null) {
      throw Exception('Google Sign-In was cancelled or failed');
    }

    // 2. Get authorization tokens for Firebase authentication.
    //    In v7, tokens are obtained via authorizationClient.
    final clientAuth = await googleUser.authorizationClient
        .authorizationForScopes(<String>['email', 'profile']);

    final accessToken = clientAuth?.accessToken;

    // Attempt to get server auth code (may be null on some platforms/flows)
    GoogleSignInServerAuthorization? serverAuth;
    try {
      serverAuth = await googleUser.authorizationClient
          .authorizeServer(<String>['email', 'profile']);
    } catch (_) {
      // Server auth code is not available on all platforms — not fatal
    }

    final serverAuthCode = serverAuth?.serverAuthCode;

    if (accessToken == null && serverAuthCode == null) {
      throw Exception(
          'Failed to obtain Google authorization tokens. Cannot sign in with Firebase.');
    }

    // 3. Sign into Firebase with Google credential
    final credential = GoogleAuthProvider.credential(
      accessToken: accessToken,
    );

    await FirebaseAuth.instance.signInWithCredential(credential);

    // 4. Get Firebase ID token (verified, trusted by our backend)
    final firebaseToken =
        await FirebaseAuth.instance.currentUser?.getIdToken();

    if (firebaseToken == null) {
      throw Exception('Failed to get Firebase ID token after Google sign-in');
    }

    return GoogleSignInResult(
      idToken: firebaseToken,
      email: googleUser.email,
      name: googleUser.displayName ?? 'User',
      photoUrl: googleUser.photoUrl,
    );
  }

  /// Signs out from Google and Firebase.
  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
      await FirebaseAuth.instance.signOut();
      _currentUser = null;
    } catch (e) {
      debugPrint('[GoogleAuth] Sign out failed: $e');
    }
  }

  /// Returns true if a user is currently authenticated with Google.
  /// In v7, user state is tracked via the [authenticationEvents] stream.
  bool get isSignedIn => _currentUser != null;

  /// Dispose subscriptions (call on app shutdown if needed).
  void dispose() {
    _authSubscription?.cancel();
  }
}
