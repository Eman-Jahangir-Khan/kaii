import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_repository.dart';

/// Poori app mein yehi ek instance use hoga
final callRepo = CallRepository();

/// Call ki halat: ringing -> accepted -> ended
/// (ya declined / cancelled / missed)
class CallRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _calls =>
      _db.collection('calls');

  /// Jis call par abhi screen khuli hai (taake incoming screen dobara na khule)
  String? activeCallId;

  /// Naya call shuru karo, call id wapis deta hai
  Future<String> startCall({
    required String otherUid,
    required String otherName,
    String otherPhoto = '',
    required bool video,
  }) async {
    final me = await chatRepo.getUser(_uid);
    final ref = _calls.doc();
    await ref.set({
      'callerId': _uid,
      'calleeId': otherUid,
      'participants': [_uid, otherUid],
      'callerName': (me?['username'] as String?) ?? '',
      'callerPhoto': (me?['photoUrl'] as String?) ?? '',
      'calleeName': otherName,
      'calleePhoto': otherPhoto,
      'type': video ? 'video' : 'voice',
      'status': 'ringing',
      'createdAt': FieldValue.serverTimestamp(),
      'answeredAt': null,
      'endedAt': null,
    });
    return ref.id;
  }

  /// Mujhe aane wali ringing calls
  Stream<QuerySnapshot<Map<String, dynamic>>> incomingCalls() {
    return _calls
        .where('calleeId', isEqualTo: _uid)
        .where('status', isEqualTo: 'ringing')
        .snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> callStream(String id) =>
      _calls.doc(id).snapshots();

  /// Meri call history (index se bachne ke liye sort app mein hota hai)
  Stream<QuerySnapshot<Map<String, dynamic>>> historyStream() {
    return _calls
        .where('participants', arrayContains: _uid)
        .limit(100)
        .snapshots();
  }

  Future<void> accept(String id) => _calls.doc(id).update({
    'status': 'accepted',
    'answeredAt': FieldValue.serverTimestamp(),
  });

  Future<void> decline(String id) =>
      _calls.doc(id).update({'status': 'declined'});

  /// Caller ne ring ke dauran hi cut kar di
  Future<void> cancel(String id) =>
      _calls.doc(id).update({'status': 'cancelled'});

  /// Kisi ne utha hi nahi
  Future<void> markMissed(String id) =>
      _calls.doc(id).update({'status': 'missed'});

  /// Call history se sirf MERE liye hatao (doosre ki history mein rehti hai)
  Future<void> deleteForMe(List<String> ids) async {
    final batch = _db.batch();
    for (final id in ids) {
      batch.update(_calls.doc(id), {
        'deletedFor': FieldValue.arrayUnion([_uid]),
      });
    }
    await batch.commit();
  }

  Future<void> end(String id) => _calls.doc(id).update({
    'status': 'ended',
    'endedAt': FieldValue.serverTimestamp(),
  });
}