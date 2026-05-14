import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../api/api_client.dart';
import '../models/user_model.dart';

/// Handles Google Sign-In flow via Firebase Auth and integration with the Farmaa backend.
class GoogleAuthService {
  GoogleAuthService._();
  static final GoogleAuthService instance = GoogleAuthService._();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId:
        '603178299511-c40kmarpdjg1ntjjcebgmnlj7t521dvg.apps.googleusercontent.com',
  );

  /// Signs in with Google, authenticates with Firebase, then syncs with backend.
  Future<({UserModel user, String token})> signIn() async {
    // 1. Trigger Google Sign-In UI
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Google Sign-In was cancelled');
    }

    // 2. Get Google auth credentials
    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null) {
      throw Exception('Failed to get Google ID token');
    }

    // 3. Sign into Firebase with Google credential
    final credential = GoogleAuthProvider.credential(
      idToken: idToken,
      accessToken: accessToken,
    );
    await FirebaseAuth.instance.signInWithCredential(credential);

    // 4. Get Firebase ID token
    final firebaseToken =
        await FirebaseAuth.instance.currentUser?.getIdToken();

    // 5. Sync with backend using Firebase ID token
    try {
      final response = await ApiClient().dio.post('/auth/firebase', data: {
        'firebase_id_token': firebaseToken ?? idToken,
        'email': googleUser.email,
        'name': googleUser.displayName ?? 'User',
        'profile_image': googleUser.photoUrl,
      });

      final data = response.data as Map<String, dynamic>;
      final token = firebaseToken ?? data['access_token']?.toString() ?? '';
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      return (user: user, token: token);
    } catch (e) {
      debugPrint('[GoogleAuth] Backend sync failed, creating local session: $e');
      return _createLocalSession(googleUser, firebaseToken ?? '');
    }
  }

  /// Signs out from Google and Firebase.
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('[GoogleAuth] Sign out failed: $e');
    }
  }

  /// Check if currently signed in with Google.
  Future<bool> isSignedIn() async {
    return _googleSignIn.isSignedIn();
  }

  Future<({UserModel user, String token})> _createLocalSession(
    GoogleSignInAccount googleUser,
    String token,
  ) async {
    final localUser = UserModel(
      id: 'google_${googleUser.id}',
      name: googleUser.displayName ?? 'Google User',
      email: googleUser.email,
      role: 'buyer',
      isVerified: true,
      profileImageUrl: googleUser.photoUrl,
      createdAt: DateTime.now(),
    );
    return (user: localUser, token: token);
  }
}
