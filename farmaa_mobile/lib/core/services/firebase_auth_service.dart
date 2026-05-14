import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Wraps Firebase Authentication SDK for email/password auth.
class FirebaseAuthService {
  FirebaseAuthService._();
  static final FirebaseAuthService instance = FirebaseAuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Current Firebase user (null if signed out).
  User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Register a new user with email and password.
  Future<UserCredential> register({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseError(e);
    }
  }

  /// Sign in with email and password.
  Future<UserCredential> login({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseError(e);
    }
  }

  /// Get the current user's Firebase ID token for backend API calls.
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    return await _auth.currentUser?.getIdToken(forceRefresh);
  }

  /// Send a password reset email.
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseError(e);
    }
  }

  /// Sign out from Firebase.
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Maps Firebase error codes to user-friendly messages.
  Exception _mapFirebaseError(FirebaseAuthException e) {
    debugPrint('[FirebaseAuth] Error: ${e.code} - ${e.message}');
    switch (e.code) {
      case 'email-already-in-use':
        return Exception('This email is already registered. Please login instead.');
      case 'invalid-email':
        return Exception('Please enter a valid email address.');
      case 'weak-password':
        return Exception('Password is too weak. Use at least 6 characters.');
      case 'user-not-found':
        return Exception('No account found with this email.');
      case 'wrong-password':
        return Exception('Incorrect password. Please try again.');
      case 'user-disabled':
        return Exception('This account has been disabled.');
      case 'too-many-requests':
        return Exception('Too many attempts. Please try again later.');
      case 'invalid-credential':
        return Exception('Invalid email or password.');
      default:
        return Exception(e.message ?? 'Authentication failed.');
    }
  }
}
