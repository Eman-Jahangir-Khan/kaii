import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'notification_service.dart';
import 'presence_service.dart';

class UsernameTakenException implements Exception {
  @override
  String toString() => 'Username unavailable.';
}

/// Username 7 din mein sirf ek baar badal sakte hain
class UsernameCooldownException implements Exception {
  final DateTime allowedAt;
  UsernameCooldownException(this.allowedAt);

  @override
  String toString() {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final d = allowedAt.toLocal();
    return 'You can change your username again on '
        '${d.day} ${months[d.month - 1]} ${d.year}.';
  }
}

/// Username ke rules ek hi jagah (signup, Google signup, edit teeno yahi use karte hain)
String? validateUsername(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return 'Username is required';
  if (name.length < 6) return 'At least 6 characters';
  if (name.length > 20) return 'At most 20 characters';
  if (!RegExp(r'^[a-z0-9_.]+$').hasMatch(name)) {
    return 'Only small letters, numbers, underscore and dot';
  }
  if (name.startsWith('.') || name.endsWith('.')) {
    return 'Username cannot start or end with a dot';
  }
  if (name.contains('..')) {
    return 'Username cannot have two dots in a row';
  }
  return null;
}

class AccountDeletedException implements Exception {
  @override
  String toString() => 'This account has been deleted.';
}

/// Poori app mein yehi ek instance use hoga
final authRepo = AuthRepository();

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Username badalne ke beech kam az kam itna gap
  static const Duration usernameCooldown = Duration(days: 7);

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

  /// Username badlo: naya unique hona chahiye, aur pichli tabdeeli ko 7 din guzar chuke hon.
  /// Sab kuch ek transaction mein: naya naam reserve, purana free, users doc update.
  Future<void> changeUsername(String newUsername) async {
    final user = _auth.currentUser!;
    final next = newUsername.trim().toLowerCase();
    final err = validateUsername(next);
    if (err != null) throw Exception(err);

    final userRef = _db.collection('users').doc(user.uid);

    await _db.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      final data = userSnap.data() ?? <String, dynamic>{};
      final old = ((data['username'] as String?) ?? '').trim();
      if (next == old) return;

      final last = data['usernameChangedAt'];
      if (last is Timestamp) {
        final allowedAt = last.toDate().add(usernameCooldown);
        if (DateTime.now().isBefore(allowedAt)) {
          throw UsernameCooldownException(allowedAt);
        }
      }

      final newRef = _db.collection('usernames').doc(next);
      final newSnap = await tx.get(newRef);
      if (newSnap.exists) throw UsernameTakenException();

      tx.set(newRef, {'uid': user.uid});
      if (old.isNotEmpty) {
        tx.delete(_db.collection('usernames').doc(old));
      }
      tx.update(userRef, {
        'username': next,
        'usernameChangedAt': FieldValue.serverTimestamp(),
      });
    });
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

      final cred = await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      await _blockIfDeleted(cred.user!);
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
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await _blockIfDeleted(cred.user!);
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
  /// password = email users ke liye, Google users ke liye null
  Future<void> deleteAccount({String? password}) async {
    final user = _auth.currentUser!;
    final uid = user.uid;

    // 1) Re-authenticate
    final isGoogle =
    user.providerData.any((p) => p.providerId == 'google.com');
    if (isGoogle) {
      if (!_googleReady) {
        await GoogleSignIn.instance.initialize();
        _googleReady = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw Exception('No Google ID token');
      await user.reauthenticateWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    } else {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(
          email: user.email!,
          password: password ?? '',
        ),
      );
    }

    // 2) Safety flag + presence/token band (auth abhi baqi hai)
    final userRef = _db.collection('users').doc(uid);
    final username = (await userRef.get()).data()?['username'] as String?;
    await userRef.update({'isDeleted': true});
    await presenceService.stop(); // warna delete ke baad doc dobara ban sakta hai
    try {
      await NotificationService.instance.removeToken();
    } catch (_) {}

    // 3) Firestore cleanup
    final batch = _db.batch();
    if (username != null && username.isNotEmpty) {
      // usernames/{name} ke doc mein {'uid': ...} hai, uid se dhoondo
      final unameDocs = await _db
          .collection('usernames')
          .where('uid', isEqualTo: uid)
          .get();
      for (final d in unameDocs.docs) {
        batch.delete(d.reference);
      }
      if (username != null && username.isNotEmpty) {
        batch.delete(_db.collection('usernames').doc(username)); // backup
      }
    }
    final statuses = await _db
        .collection('statuses')
        .where('ownerId', isEqualTo: uid)
        .get();
    for (final d in statuses.docs) {
      batch.delete(d.reference);
    }
    batch.delete(userRef);
    await batch.commit();

    // 4) Auth user delete (sab se last)
    try {
      await user.delete();
    } catch (e) {
      await userRef.set({'isDeleted': true}); // login block rahe
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
      await _auth.signOut();
      rethrow;
    }
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }

  /// Delete-fail hone wale account ko dubara login se roko
  Future<void> _blockIfDeleted(User user) async {
    final snap = await _db.collection('users').doc(user.uid).get();
    if (snap.data()?['isDeleted'] == true) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
      await _auth.signOut();
      throw AccountDeletedException();
    }
  }
}

/// Errors ko user-friendly message mein badalta hai
String authErrorMessage(Object e) {
  if (e is UsernameTakenException) return e.toString();
  if (e is AccountDeletedException) return e.toString();
  if (e is UsernameCooldownException) return e.toString();
  if (e is FirebaseException && e.code == 'permission-denied') {
    return 'This change is not allowed right now.';
  }
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