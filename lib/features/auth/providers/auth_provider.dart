import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/user_model.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final String? error;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.error,
  });

  AuthState copyWith({AuthStatus? status, UserModel? user, String? error}) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        error: error,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreamSubscription<User?>? _authSubscription;

  AuthNotifier() : super(const AuthState()) {
    _initAuthListener();
  }

  void _initAuthListener() {
    _updateUser(_auth.currentUser);
    _authSubscription = _auth.authStateChanges().listen((firebaseUser) {
      _updateUser(firebaseUser);
    });
  }

  void _updateUser(User? firebaseUser) {
    if (firebaseUser != null) {
      state = AuthState(
        status: AuthStatus.authenticated,
        user: _buildUserModel(firebaseUser),
      );
    } else {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  bool _isAdminUser(User user) {
    final email = user.email?.toLowerCase() ?? '';
    return email.contains('admin') ||
        email == 'admin@garba.com' ||
        email.endsWith('@garba.admin');
  }

  UserModel _buildUserModel(User firebaseUser,
      {String? customName, String? customPhone}) {
    final name = customName ??
        (firebaseUser.displayName?.isNotEmpty == true
            ? firebaseUser.displayName!
            : (firebaseUser.email?.isNotEmpty == true
                ? firebaseUser.email!.split('@').first
                : (firebaseUser.phoneNumber ?? 'Garba Dancer')));

    return UserModel(
      id: firebaseUser.uid,
      name: name,
      email: firebaseUser.email ?? '',
      phone: customPhone ?? firebaseUser.phoneNumber,
      photo: firebaseUser.photoURL,
      isAdmin: _isAdminUser(firebaseUser),
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    String? phone,
  }) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await credential.user?.updateDisplayName(name);

      state = AuthState(
        status: AuthStatus.authenticated,
        user: _buildUserModel(
          credential.user!,
          customName: name,
          customPhone: phone,
        ),
      );
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        error: _mapFirebaseError(e),
      );
    } catch (_) {
      state = state.copyWith(
        status: AuthStatus.error,
        error: 'Something went wrong. Please try again.',
      );
    }
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      state = AuthState(
        status: AuthStatus.authenticated,
        user: _buildUserModel(credential.user!),
      );
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        error: _mapFirebaseError(e),
      );
    } catch (_) {
      state = state.copyWith(
        status: AuthStatus.error,
        error: 'Something went wrong. Please try again.',
      );
    }
  }

  Future<String> forgotPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return 'Reset email sent. Please check your inbox.';
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapFirebaseError(e));
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> updateProfile({
    String? name,
    String? phone,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      if (name != null) await user.updateDisplayName(name);
      state = state.copyWith(
        user: UserModel(
          id: user.uid,
          name: name ?? user.displayName ?? '',
          email: user.email ?? '',
        ),
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to update profile.');
    }
  }

  /// Sends a verification email to the currently signed-in user,
  /// if they haven't verified yet.
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  /// Reloads the current user from Firebase and returns whether
  /// their email is now verified. Call this when the user taps
  /// "I've verified, continue" on the verify-email screen.
  Future<bool> checkEmailVerified() async {
    await _auth.currentUser?.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  /// Permanently deletes the current user's Firebase account.
  /// Throws an Exception with a user-friendly message on failure.
  ///
  /// Note: Firebase requires a *recent* login for security-sensitive actions
  /// like account deletion. If the user signed in a while ago, this will
  /// throw a 'requires-recent-login' error — in that case, log out and log
  /// back in, then try deleting again.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.delete();
      state = const AuthState(status: AuthStatus.unauthenticated);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw Exception(
          'For security, please log out and log back in, then try deleting your account again.',
        );
      }
      throw Exception(_mapFirebaseError(e));
    }
  }

  String _mapFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Use at least 8 characters.';
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

final currentUserProvider = Provider<UserModel?>(
  (ref) => ref.watch(authProvider).user,
);