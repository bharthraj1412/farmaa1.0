import 'package:firebase_auth/firebase_auth.dart';

/// Wraps Firebase Authentication SDK — only token management, no email/password.
class FirebaseAuthService {
  FirebaseAuthService._();
  static final FirebaseAuthService instance = FirebaseAuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Current Firebase user (null if signed out).
  User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Get the current user's Firebase ID token for backend API calls.
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    return await _auth.currentUser?.getIdToken(forceRefresh);
  }

  /// Sign out from Firebase.
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
