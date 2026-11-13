import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'notification_service.dart';
import 'presence_service.dart';

class UsernameTakenException implements Exception {
  @override
  String toString() => 'This username is already taken.';
}

/// Poori app mein yehi ek instance use hoga
final authRepo = AuthRepository();

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// reload() ke baad bhi fire hota hai, isliye authStateChanges ki jagah ye
  Stream<User?> get userChanges => _auth.userChanges();
  User? get currentUser => _auth.currentUser;

  Future<bool> isUsernameAvailable(String username) async {
    final doc = await _db
        .collection('usernames')
        .doc(username.trim().toLowerCase())
        .get();
    return !doc.exists;
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    final uname = username.trim().toLowerCase();

    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user!;

    try {
      await _db.runTransaction((tx) async {
        final unameRef = _db.collection('usernames').doc(uname);
        final snap = await tx.get(unameRef);
        if (snap.exists) throw UsernameTakenException();

        tx.set(unameRef, {'uid': user.uid});
        tx.set(_db.collection('users').doc(user.uid), {
          'uid': user.uid,
          'email': user.email,
          'username': uname,
          'name': '',
          'photoUrl': '',
          'about': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      // adha account na bache (delete fail bhi ho to asli error dikhao)
      try {
        await user.delete();
      } catch (_) {}
      rethrow;
    }

    // email na bhi jaye to account theek hai, verify screen se resend ho jata hai
    try {
      await user.sendEmailVerification();
    } catch (_) {}
  }

  bool _googleReady = false;

  /// true = sign in ho gaya, false = user ne cancel kar diya
  Future<bool> signInWithGoogle() async {
    try {
      if (!_googleReady) {
        await GoogleSignIn.instance.initialize();
        _googleReady = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw Exception('No Google ID token');

      await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      return true;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    }
  }

  /// users/{uid} document banta/badalta hai to AuthGate ko pata chal jata hai
  Stream<DocumentSnapshot<Map<String, dynamic>>> profileStream(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .snapshots(includeMetadataChanges: true);
  }

  /// Google se aaye naye user ka profile + username (ek transaction mein)
  Future<void> createProfile({required String username}) async {
    final user = _auth.currentUser!;
    final uname = username.trim().toLowerCase();

    await _db.runTransaction((tx) async {
      final unameRef = _db.collection('usernames').doc(uname);
      final snap = await tx.get(unameRef);
      if (snap.exists) throw UsernameTakenException();

      tx.set(unameRef, {'uid': user.uid});
      tx.set(_db.collection('users').doc(user.uid), {
        'uid': user.uid,
        'email': user.email,
        'username': uname,
        'name': user.displayName ?? '',
        'photoUrl': user.photoURL ?? '',
        'about': '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> resendVerificationEmail() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  Future<bool> checkEmailVerified() async {
    await _auth.currentUser?.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> logout() async {
    await presenceService.stop(); // signOut se pehle, warna uid nahi milta
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await NotificationService.instance.removeToken();
    await _auth.signOut();
  }
}

/// Errors ko user-friendly message mein badalta hai
String authErrorMessage(Object e) {
  if (e is UsernameTakenException) return e.toString();
  if (e is GoogleSignInException) {
    return 'Google sign-in failed (${e.code.name}): ${e.description}';
  }
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again in a while.';
      case 'account-exists-with-different-credential':
        return 'An account with this email already exists. Sign in with your password.';
      case 'network-request-failed':
        return 'No internet connection.';
      default:
        return e.message ?? 'Something went wrong.';
    }
  }
  return 'Something went wrong. Please try again.';
}