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
class GoogleAuthService {
  GoogleAuthService._();
  static final GoogleAuthService instance = GoogleAuthService._();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId:
        '603178299511-igtc5nncdi8a56bt0c9a0rrks4uv9s9b.apps.googleusercontent.com',
  );

  /// Performs Google Sign-In, authenticates with Firebase, returns the ID token and user info.
  Future<GoogleSignInResult> signIn() async {
    // 1. Trigger Google Sign-In UI
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Google Sign-In was cancelled');
    }

    // 2. Get Google auth credentials
    final googleAuth = await googleUser.authentication;
    final googleIdToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (googleIdToken == null) {
      throw Exception('Failed to get Google ID token');
    }

    // 3. Sign into Firebase with Google credential
    final credential = GoogleAuthProvider.credential(
      idToken: googleIdToken,
      accessToken: accessToken,
    );
    await FirebaseAuth.instance.signInWithCredential(credential);

    // 4. Get Firebase ID token (verified, trusted)
    final firebaseToken =
        await FirebaseAuth.instance.currentUser?.getIdToken();

    if (firebaseToken == null) {
      throw Exception('Failed to get Firebase ID token');
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
      await _googleSignIn.signOut();
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('[GoogleAuth] Sign out failed: $e');
    }
  }

  /// Check if currently signed in with Google.
  Future<bool> isSignedIn() async {
    return _googleSignIn.isSignedIn();
  }
}
