import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_repository.dart';

/// Poori app mein yehi ek instance use hoga
final groupRepo = GroupRepository();

/// Firestore structure:
///
/// groups/{groupId}
///   name, photoUrl, createdBy, createdAt
///   admins:  [uid]
///   members: [uid]
///   joinedAt:  {uid: Timestamp}   (is se pehle ke messages naye member ko nahi dikhte)
///   lastRead:  {uid: Timestamp}   (seen ticks ke liye)
///   unread:    {uid: int}
///   typing:    {uid: Timestamp}
///   lastMessage, lastMessageAt, lastSenderId, lastSenderName
///
/// groups/{groupId}/messages/{messageId}
///   senderId, senderName, type (text | image | system), text, createdAt
///   imageUrl, width, height, replyTo, reactions, edited, deletedForAll, deletedFor
class GroupRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _groups =>
      _db.collection('groups');

  CollectionReference<Map<String, dynamic>> _msgs(String groupId) =>
      _groups.doc(groupId).collection('messages');

  /// Mera username (message ke saath save hota hai, taake har bar lookup na ho)
  Future<String> myName() async {
    final u = await chatRepo.getUser(_uid);
    return (u?['username'] as String?) ?? '';
  }

  // -------------------------------------------------------------------------
  // Contacts (jin se chat accepted hai) — group ke members yahin se chune jate hain
  // -------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> loadContacts() async {
    final snap = await _db
        .collection('chats')
        .where('participants', arrayContains: _uid)
        .get();

    final uids = <String>{};
    for (final d in snap.docs) {
      final data = d.data();
      final status = data['status'] as String?;
      // purani chats (status nahi) accepted maani jati hain
      if (status != null && status != 'accepted') continue;
      final p = List<String>.from(data['participants'] ?? const []);
      for (final u in p) {
        if (u != _uid) uids.add(u);
      }
    }

    final users = await Future.wait(uids.map(chatRepo.getUser));
    final list = users.whereType<Map<String, dynamic>>().toList()
      ..sort((a, b) => ((a['username'] as String?) ?? '')
          .compareTo((b['username'] as String?) ?? ''));
    return list;
  }

  // -------------------------------------------------------------------------
  // Streams
  // -------------------------------------------------------------------------

  /// Meri saari groups, naye message wali upar
  /// (pehli baar console mein index banane ka link aayega — ek baar bana lena)
  Stream<QuerySnapshot<Map<String, dynamic>>> groupsStream() {
    return _groups
        .where('members', arrayContains: _uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> groupDocStream(
      String groupId) {
    return _groups.doc(groupId).snapshots();
  }

  /// Naye messages pehle (ListView reverse: true ke liye)
  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(
      String groupId, {
        int limit = 50,
      }) {
    return _msgs(groupId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  // -------------------------------------------------------------------------
  // Create
  // -------------------------------------------------------------------------

  Future<String> createGroup({
    required String name,
    String photoUrl = '',
    required List<String> memberUids,
  }) async {
    final me = await myName();
    final ref = _groups.doc();
    final members = <String>{_uid, ...memberUids}.toList();
    final groupName = name.trim();
    final text = '$me created group "$groupName"';

    final batch = _db.batch();
    batch.set(ref, {
      'name': groupName,
      'photoUrl': photoUrl,
      'createdBy': _uid,
      'createdAt': FieldValue.serverTimestamp(),
      'admins': [_uid],
      'members': members,
      'joinedAt': {for (final m in members) m: FieldValue.serverTimestamp()},
      'lastRead': {_uid: FieldValue.serverTimestamp()},
      'unread': {for (final m in members) m: 0},
      'lastMessage': text,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSenderId': '',
      'lastSenderName': '',
    });
    batch.set(ref.collection('messages').doc(), _system(text));
    await batch.commit();
    return ref.id;
  }

  Map<String, dynamic> _system(String text) => {
    'type': 'system',
    'senderId': _uid,
    'senderName': '',
    'text': text,
    'createdAt': FieldValue.serverTimestamp(),
  };

  // -------------------------------------------------------------------------
  // Send
  // -------------------------------------------------------------------------

  Future<void> sendMessage({
    required String groupId,
    required List<String> members,
    required String text,
    Map<String, dynamic>? replyTo,
  }) async {
    final body = text.trim();
    if (body.isEmpty) return;
    await _send(
      groupId: groupId,
      members: members,
      preview: body,
      message: {
        'type': 'text',
        'text': body,
        if (replyTo != null) 'replyTo': replyTo,
      },
    );
  }

  Future<void> sendImage({
    required String groupId,
    required List<String> members,
    required String imageUrl,
    int? width,
    int? height,
    Map<String, dynamic>? replyTo,
  }) {
    return _send(
      groupId: groupId,
      members: members,
      preview: '📷 Photo',
      message: {
        'type': 'image',
        'imageUrl': imageUrl,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        'text': '',
        if (replyTo != null) 'replyTo': replyTo,
      },
    );
  }

  Future<void> _send({
    required String groupId,
    required List<String> members,
    required String preview,
    required Map<String, dynamic> message,
  }) async {
    final me = await myName();
    final groupRef = _groups.doc(groupId);
    final batch = _db.batch();

    batch.update(groupRef, {
      'lastMessage': preview,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSenderId': _uid,
      'lastSenderName': me,
      'lastRead.$_uid': FieldValue.serverTimestamp(),
      'unread.$_uid': 0,
      'typing.$_uid': FieldValue.delete(),
      for (final m in members)
        if (m != _uid) 'unread.$m': FieldValue.increment(1),
    });

    batch.set(_msgs(groupId).doc(), {
      ...message,
      'senderId': _uid,
      'senderName': me,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // -------------------------------------------------------------------------
  // Read / typing
  // -------------------------------------------------------------------------

  /// Group kholne / naya message aane par: mera unread 0 aur "seen" waqt update
  Future<void> markRead(String groupId) {
    return _groups.doc(groupId).update({
      'unread.$_uid': 0,
      'lastRead.$_uid': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setTyping(String groupId, bool typing) {
    return _groups.doc(groupId).update({
      'typing.$_uid':
      typing ? FieldValue.serverTimestamp() : FieldValue.delete(),
    });
  }

  // -------------------------------------------------------------------------
  // Message actions
  // -------------------------------------------------------------------------

  Future<void> setReaction({
    required String groupId,
    required String messageId,
    String? emoji,
  }) {
    return _msgs(groupId)
        .doc(messageId)
        .update({'reactions.$_uid': emoji ?? FieldValue.delete()});
  }

  Future<void> editMessage({
    required String groupId,
    required String messageId,
    required String newText,
    bool updateLastMessage = false,
  }) {
    final batch = _db.batch();
    batch.update(_msgs(groupId).doc(messageId), {
      'text': newText,
      'edited': true,
      'editedAt': FieldValue.serverTimestamp(),
    });
    if (updateLastMessage) {
      batch.update(_groups.doc(groupId), {'lastMessage': newText});
    }
    return batch.commit();
  }

  Future<void> deleteMessagesForMe({
    required String groupId,
    required List<String> messageIds,
  }) {
    final batch = _db.batch();
    for (final id in messageIds) {
      batch.update(_msgs(groupId).doc(id), {
        'deletedFor': FieldValue.arrayUnion([_uid]),
      });
    }
    return batch.commit();
  }

  /// Sab ke liye delete (apne messages, ya admin kisi ka bhi)
  Future<void> deleteMessagesForEveryone({
    required String groupId,
    required List<String> messageIds,
    bool updateLastMessage = false,
  }) {
    final batch = _db.batch();
    for (final id in messageIds) {
      batch.update(_msgs(groupId).doc(id), {
        'deletedForAll': true,
        'text': '',
      });
    }
    if (updateLastMessage) {
      batch.update(
          _groups.doc(groupId), {'lastMessage': 'This message was deleted'});
    }
    return batch.commit();
  }

  // -------------------------------------------------------------------------
  // Members & group info
  // -------------------------------------------------------------------------

  /// users: [{uid, username}, ...]
  Future<void> addMembers({
    required String groupId,
    required List<Map<String, dynamic>> users,
  }) async {
    if (users.isEmpty) return;
    final me = await myName();
    final names = users.map((u) => u['username'] ?? '').join(', ');
    final text = '$me added $names';

    final batch = _db.batch();
    batch.update(_groups.doc(groupId), {
      'members': FieldValue.arrayUnion(users.map((u) => u['uid']).toList()),
      for (final u in users) ...{
        'joinedAt.${u['uid']}': FieldValue.serverTimestamp(),
        'unread.${u['uid']}': 0,
      },
      'lastMessage': text,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSenderId': '',
      'lastSenderName': '',
    });
    batch.set(_msgs(groupId).doc(), _system(text));
    await batch.commit();
  }

  Future<void> removeMember({
    required String groupId,
    required String uid,
    required String username,
  }) async {
    final me = await myName();
    final text = '$me removed $username';
    final batch = _db.batch();
    batch.update(_groups.doc(groupId), {
      'members': FieldValue.arrayRemove([uid]),
      'admins': FieldValue.arrayRemove([uid]),
      'lastMessage': text,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSenderId': '',
      'lastSenderName': '',
    });
    batch.set(_msgs(groupId).doc(), _system(text));
    await batch.commit();
  }

  Future<void> setAdmin({
    required String groupId,
    required String uid,
    required String username,
    required bool admin,
  }) async {
    final me = await myName();
    final text =
    admin ? '$me made $username an admin' : '$me removed $username as admin';
    final batch = _db.batch();
    batch.update(_groups.doc(groupId), {
      'admins':
      admin ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid]),
    });
    batch.set(_msgs(groupId).doc(), _system(text));
    await batch.commit();
  }

  /// Naam / photo badlo. Khali chhoda hua field waisa hi rahega.
  Future<void> updateInfo({
    required String groupId,
    String? name,
    String? photoUrl,
  }) async {
    final me = await myName();
    final batch = _db.batch();
    final updates = <String, dynamic>{};
    if (name != null && name.trim().isNotEmpty) {
      updates['name'] = name.trim();
      batch.set(_msgs(groupId).doc(),
          _system('$me changed the group name to "${name.trim()}"'));
    }
    if (photoUrl != null) {
      updates['photoUrl'] = photoUrl;
      batch.set(_msgs(groupId).doc(), _system('$me changed the group photo'));
    }
    if (updates.isEmpty) return;
    batch.update(_groups.doc(groupId), updates);
    await batch.commit();
  }

  /// Group chhodo. Akela admin ho aur doosre members hon to unme se ek admin ban jata hai.
  Future<void> leaveGroup(String groupId) async {
    final me = await myName();
    final ref = _groups.doc(groupId);
    final data = (await ref.get()).data();
    if (data == null) return;

    final members = List<String>.from(data['members'] ?? const []);
    final admins = List<String>.from(data['admins'] ?? const []);
    final others = members.where((m) => m != _uid).toList();
    final otherAdmins = admins.where((a) => a != _uid).toList();

    // Pehle (jab tak main admin hoon) naya admin bana do, warna group be-admin reh jayega
    if (admins.contains(_uid) && otherAdmins.isEmpty && others.isNotEmpty) {
      await ref.update({
        'admins': FieldValue.arrayUnion([others.first]),
      });
    }

    final batch = _db.batch();
    batch.set(_msgs(groupId).doc(), _system('$me left'));
    batch.update(ref, {
      'members': FieldValue.arrayRemove([_uid]),
      'admins': FieldValue.arrayRemove([_uid]),
    });
    await batch.commit();
  }
}