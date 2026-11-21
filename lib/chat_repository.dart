import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';


/// Poori app mein yehi ek instance use hoga
final chatRepo = ChatRepository();
enum ChatLink { none, accepted, requestSent, requestReceived, declined }

class ChatRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  /// Do users ke beech ka rishta


  String get _uid => _auth.currentUser!.uid;

  /// Dono users ke liye hamesha ek hi id banti hai
  static String chatIdFor(String a, String b) {
    final ids = [a, b]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  String chatIdWith(String otherUid) => chatIdFor(_uid, otherUid);

  /// Username ke shuru ke hisse se users dhoondo (khud ko chhor kar)
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return [];

    final snap = await _db
        .collection('users')
        .where('username', isGreaterThanOrEqualTo: q)
        .where('username', isLessThan: '$q\uf8ff')
        .limit(10)
        .get();

    return snap.docs
        .map((d) => d.data())
        .where((u) => u['uid'] != _uid)
        .toList();
  }

  /// Chat ko mere liye unread mark karo / hatao
  Future<void> setMarkedUnread(String chatId, bool marked) {
    return _db.collection('chats').doc(chatId).update({
      'markedUnread': marked
          ? FieldValue.arrayUnion([_uid])
          : FieldValue.arrayRemove([_uid]),
    });
  }

  /// Chat ke user ko block / unblock karo (mere liye)
  Future<void> setBlocked(String chatId, bool blocked) {
    return _db.collection('chats').doc(chatId).update({
      'blockedBy': blocked
          ? FieldValue.arrayUnion([_uid])
          : FieldValue.arrayRemove([_uid]),
    });
  }

  /// Is chat ka background rang (sirf mere liye). null = default
  Future<void> setChatTheme(String chatId, String? key) {
    return _db.collection('chats').doc(chatId).update({
      'chatTheme.$_uid': key ?? FieldValue.delete(),
    });
  }

  /// Ye messages sirf meri taraf se delete karo
  Future<void> deleteMessagesForMe({
    required String chatId,
    required List<String> messageIds,
  }) async {
    final msgs = _db.collection('chats').doc(chatId).collection('messages');
    final batch = _db.batch();
    for (final id in messageIds) {
      batch.update(msgs.doc(id), {
        'deletedFor': FieldValue.arrayUnion([_uid]),
      });
    }
    await batch.commit();
  }

  /// Home tile ke liye meri taraf ka last message (delete for me ke baad)
  Future<void> setMyPreview({
    required String chatId,
    required Timestamp base,
    required String text,
    required String senderId,
  }) {
    return _db.collection('chats').doc(chatId).update({
      'myPreview.$_uid': {'base': base, 'text': text, 'senderId': senderId},
    });
  }

  /// Ye messages sab ke liye delete karo (text khali, placeholder dikhega)
  Future<void> deleteMessagesForEveryone({
    required String chatId,
    required List<String> messageIds,
    bool updateLastMessage = false,
  }) async {
    final chatRef = _db.collection('chats').doc(chatId);
    final batch = _db.batch();

    for (final id in messageIds) {
      batch.update(chatRef.collection('messages').doc(id), {
        'deletedForAll': true,
        'text': '',
      });
    }
    // Agar ye chat ka aakhri message tha to home tile bhi badal do
    if (updateLastMessage) {
      batch.update(chatRef, {'lastMessage': 'This message was deleted'});
    }

    await batch.commit();
  }

  /// Apne message ka text badlo
  Future<void> editMessage({
    required String chatId,
    required String messageId,
    required String newText,
    bool updateLastMessage = false,
  }) {
    final chatRef = _db.collection('chats').doc(chatId);
    final batch = _db.batch();

    batch.update(chatRef.collection('messages').doc(messageId), {
      'text': newText,
      'edited': true,
      'editedAt': FieldValue.serverTimestamp(),
    });
    // Agar ye chat ka aakhri message hai to home tile bhi badal do
    if (updateLastMessage) {
      batch.update(chatRef, {'lastMessage': newText});
    }

    return batch.commit();
  }

  /// Message par meri reaction lagao. emoji null ho to hata do
  Future<void> setReaction({
    required String chatId,
    required String messageId,
    String? emoji,
  }) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({'reactions.$_uid': emoji ?? FieldValue.delete()});
  }

  /// Messages pin / unpin karo (dono users ke liye)
  Future<void> setMessagesPinned({
    required String chatId,
    required List<String> messageIds,
    required bool pinned,
  }) {
    final msgs = _db.collection('chats').doc(chatId).collection('messages');
    final batch = _db.batch();

    for (final id in messageIds) {
      batch.update(
        msgs.doc(id),
        pinned
            ? {
          'pinned': true,
          'pinnedAt': FieldValue.serverTimestamp(),
          'pinnedBy': _uid,
        }
            : {'pinned': false},
      );
    }

    // Chat ke neeche "X pinned a message" ki line (sirf pin karne par)
    if (pinned) {
      batch.set(msgs.doc(), {
        'type': 'system',
        'systemKind': 'pin',
        'senderId': _uid,
        'text': '',
        'count': messageIds.length,
        'createdAt': FieldValue.serverTimestamp(),
        'readAt': null,
      });
    }

    return batch.commit();
  }

  /// Is chat ke pin kiye hue messages (50 wali hadd se azad)
  Stream<QuerySnapshot<Map<String, dynamic>>> pinnedStream(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('pinned', isEqualTo: true)
        .snapshots();
  }

  /// Chat ke messages sirf meri taraf se clear karo (chat list mein rahegi)
  Future<void> clearChatForMe(String chatId) {
    return _db.collection('chats').doc(chatId).update({
      'clearedAt.$_uid': FieldValue.serverTimestamp(),
      'unread.$_uid': 0,
    });
  }

  /// Chat doc ko live sunne ke liye (block status ke liye)
  Stream<DocumentSnapshot<Map<String, dynamic>>> chatDocStream(String chatId) {
    return _db.collection('chats').doc(chatId).snapshots();
  }

  /// Meri saari chats, naye message wali upar
  Stream<QuerySnapshot<Map<String, dynamic>>> chatsStream() {
    return _db
        .collection('chats')
        .where('participants', arrayContains: _uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots();
  }

  ChatLink linkFromData(Map<String, dynamic>? d) {
    if (d == null) return ChatLink.none;
    final status = d['status'] as String?;
    // purani chats (status nahi) accepted maani jati hain
    if (status == null || status == 'accepted') return ChatLink.accepted;
    final by = d['requestedBy'] as String?;
    if (status == 'pending') {
      return by == _uid ? ChatLink.requestSent : ChatLink.requestReceived;
    }
    if (status == 'rejected') {
      return by == _uid ? ChatLink.declined : ChatLink.none;
    }
    return ChatLink.none;
  }

  Future<ChatLink> linkWith(String otherUid) async {
    final doc = await _db.collection('chats').doc(chatIdWith(otherUid)).get();
    return linkFromData(doc.data());
  }

  Future<Map<String, ChatLink>> linksFor(List<String> uids) async {
    final entries = await Future.wait(
      uids.map((u) async => MapEntry(u, await linkWith(u))),
    );
    return Map.fromEntries(entries);
  }

  /// Request bhejo. Samne wala pehle hi request bhej chuka ho to accept ho jati hai.
  Future<ChatLink> sendRequest(String otherUid) async {
    final ref = _db.collection('chats').doc(chatIdWith(otherUid));
    final snap = await ref.get();
    final link = linkFromData(snap.data());

    if (link == ChatLink.none) {
      final participants = [_uid, otherUid]..sort();
      await ref.set({
        'participants': participants,
        'status': 'pending',
        'requestedBy': _uid,
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': _uid,
        'unread': {_uid: 0, otherUid: 0},
      });
      return ChatLink.requestSent;
    }
    if (link == ChatLink.requestReceived) {
      await acceptRequest(otherUid);
      return ChatLink.accepted;
    }
    return link;
  }

  Future<void> acceptRequest(String otherUid) {
    return _db.collection('chats').doc(chatIdWith(otherUid)).update({
      'status': 'accepted',
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> rejectRequest(String otherUid) {
    return _db
        .collection('chats')
        .doc(chatIdWith(otherUid))
        .update({'status': 'rejected'});
  }

  /// Chat ko mere liye pin / unpin karo (har user ki apni pin)
  Future<void> setPinned(String chatId, bool pinned) {
    return _db.collection('chats').doc(chatId).update({
      'pinnedBy': pinned
          ? FieldValue.arrayUnion([_uid])
          : FieldValue.arrayRemove([_uid]),
    });
  }

  /// Chat sirf meri taraf se delete karo (samne wale ki chat waisi hi rahegi)
  Future<void> deleteChatForMe(String chatId) {
    return _db.collection('chats').doc(chatId).update({
      'deletedAt.$_uid': FieldValue.serverTimestamp(),
      'unread.$_uid': 0,
      'pinnedBy': FieldValue.arrayRemove([_uid]),
    });
  }

  /// Maine ye chat kab delete ki thi (null = kabhi nahi)
  /// Delete ya clear ka sab se naya waqt (us se pehle ke messages nahi dikhane)
  Future<Timestamp?> deletedAtFor(String chatId) async {
    final doc = await _db.collection('chats').doc(chatId).get();
    final data = doc.data();
    Timestamp? latest;
    for (final field in ['deletedAt', 'clearedAt']) {
      final map = data?[field];
      if (map is Map) {
        final v = map[_uid];
        if (v is Timestamp && (latest == null || v.compareTo(latest) > 0)) {
          latest = v;
        }
      }
    }
    return latest;
  }

  /// Ek chat ke messages, naye pehle (ListView reverse: true ke liye)
  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(
      String chatId, {
        int limit = 50,
      }) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  /// Image message bhejo (image Cloudinary pe upload ho chuki hai)
  Future<void> sendImage({
    required String otherUid,
    required String imageUrl,
    int? width,
    int? height,
    String caption = '',
    Map<String, dynamic>? replyTo,
  }) async {
    final chatId = chatIdWith(otherUid);
    final chatRef = _db.collection('chats').doc(chatId);
    final msgRef = chatRef.collection('messages').doc();
    final participants = [_uid, otherUid]..sort();
    final cap = caption.trim();

    final batch = _db.batch();

    batch.set(
      chatRef,
      {
        'participants': participants,
        'lastMessage': cap.isEmpty ? '📷 Photo' : '📷 $cap',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': _uid,
        'unread': {otherUid: FieldValue.increment(1)},
      },
      SetOptions(merge: true),
    );

    batch.set(msgRef, {
      'senderId': _uid,
      'type': 'image',
      'imageUrl': imageUrl,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      'text': cap,
      if (replyTo != null) 'replyTo': replyTo,
      'createdAt': FieldValue.serverTimestamp(),
      'readAt': null,
    });

    await batch.commit();
  }

  /// Video message bhejo (video Cloudinary pe upload ho chuki hai)
  Future<void> sendVideo({
    required String otherUid,
    required String videoUrl,
    required String thumbUrl,
    int? width,
    int? height,
    int? duration,
    Map<String, dynamic>? replyTo,
  }) async {
    final chatId = chatIdWith(otherUid);
    final chatRef = _db.collection('chats').doc(chatId);
    final msgRef = chatRef.collection('messages').doc();
    final participants = [_uid, otherUid]..sort();

    final batch = _db.batch();

    batch.set(
      chatRef,
      {
        'participants': participants,
        'lastMessage': '🎥 Video',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': _uid,
        'unread': {otherUid: FieldValue.increment(1)},
      },
      SetOptions(merge: true),
    );

    batch.set(msgRef, {
      'senderId': _uid,
      'type': 'video',
      'videoUrl': videoUrl,
      'thumbUrl': thumbUrl,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (duration != null) 'duration': duration,
      'text': '',
      if (replyTo != null) 'replyTo': replyTo,
      'createdAt': FieldValue.serverTimestamp(),
      'readAt': null,
    });

    await batch.commit();
  }

  /// Message bhejo. Pehla message chat bhi bana deta hai.
  Future<void> sendMessage({
    required String otherUid,
    required String text,
    bool forwarded = false,
    Map<String, dynamic>? replyTo,
  }) async {
    final body = text.trim();
    if (body.isEmpty) return;

    final chatId = chatIdWith(otherUid);
    final chatRef = _db.collection('chats').doc(chatId);
    final msgRef = chatRef.collection('messages').doc();
    final participants = [_uid, otherUid]..sort();

    final batch = _db.batch();

    batch.set(
      chatRef,
      {
        'participants': participants,
        'lastMessage': body,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': _uid,
        'unread': {otherUid: FieldValue.increment(1)},
      },
      SetOptions(merge: true),
    );

    batch.set(msgRef, {
      'senderId': _uid,
      'text': body,
      'type': 'text',
      if (replyTo != null) 'replyTo': replyTo,
      if (forwarded) 'forwarded': true,
      'createdAt': FieldValue.serverTimestamp(),
      'readAt': null,
    });

    await batch.commit();
  }

  Future<void> cancelRequest(String otherUid) async {
    final me = FirebaseAuth.instance.currentUser!.uid;
    final ids = [me, otherUid]..sort();
    await FirebaseFirestore.instance
        .collection('chats')
        .doc('${ids[0]}_${ids[1]}')
        .delete();
  }

  /// Chat kholne par: samne wale ke unread messages read mark karo
  /// aur apna unread counter 0 karo
  Future<void> markChatRead({
    required String chatId,
    required String otherUid,
    Timestamp? after,
  }) async {
    final chatRef = _db.collection('chats').doc(chatId);

    final unread = await chatRef
        .collection('messages')
        .where('senderId', isEqualTo: otherUid)
        .where('readAt', isNull: true)
        .limit(400)
        .get();

    // Meri delete karne ki tareekh se pehle ke messages read mark nahi karne
    final docs = unread.docs.where((d) {
      if (after == null) return true;
      final t = d.data()['createdAt'] as Timestamp?;
      return t == null || t.compareTo(after) > 0;
    }).toList();

    if (docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in docs) {
      batch.update(doc.reference, {'readAt': FieldValue.serverTimestamp()});
    }
    batch.update(chatRef, {'unread.$_uid': 0});
    await batch.commit();
  }




  final Map<String, Map<String, dynamic>> _userCache = {};

  /// Cache mein ho to foran mil jata hai (list mein flicker na ho)
  Map<String, dynamic>? cachedUser(String uid) => _userCache[uid];

  Future<Map<String, dynamic>?> getUser(String uid) async {
    final cached = _userCache[uid];
    if (cached != null) return cached;
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data();
    if (data != null) _userCache[uid] = data;
    return data;
  }

  /// Apna naam (nickname) badlo. Khali string = nickname hata do (username dikhega)
  Future<void> setMyName(String name) async {
    final value = name.trim();
    await _db.collection('users').doc(_uid).update({'name': value});
    // cache purana na rahe, warna naya naam foran nazar nahi aayega
    final c = _userCache[_uid];
    if (c != null) _userCache[_uid] = {...c, 'name': value};
  }

  // ---------------------------------------------------------------
  // Contact names: kisi ka naam sirf apne liye save karo (Instagram jaisa)
  // Firestore: users/{meri uid}/contacts/{uski uid}  ->  {name: '...'}
  // ---------------------------------------------------------------

  /// uid -> mera save kiya hua naam. Screens isay sun kar rebuild hoti hain.
  final ValueNotifier<Map<String, String>> contactNames = ValueNotifier({});
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _contactNamesSub;

  /// Login ke baad ek baar chalao (HomeScreen.initState mein)
  void startContactNames() {
    _contactNamesSub?.cancel();
    contactNames.value = {};
    _contactNamesSub = _db
        .collection('users')
        .doc(_uid)
        .collection('contacts')
        .snapshots()
        .listen((snap) {
      final m = <String, String>{};
      for (final d in snap.docs) {
        final n = ((d.data()['name'] as String?) ?? '').trim();
        if (n.isNotEmpty) m[d.id] = n;
      }
      contactNames.value = m;
    }, onError: (e) {
      debugPrint('CONTACT NAMES ERROR: $e');
      // Error ke baad listener band ho jata hai, isliye thori der baad dobara
      Future.delayed(const Duration(seconds: 15), () {
        if (FirebaseAuth.instance.currentUser != null) startContactNames();
      });
    });
  }

  /// Khali naam = save kiya hua naam hata do
  Future<void> setContactName(String otherUid, String name) async {
    final ref =
    _db.collection('users').doc(_uid).collection('contacts').doc(otherUid);
    final v = name.trim();
    if (v.isEmpty) {
      await ref.delete();
    } else {
      await ref.set({'name': v});
    }
    // listener ka intezar kiye bina foran screens mein dikhao
    final m = Map<String, String>.from(contactNames.value);
    if (v.isEmpty) {
      m.remove(otherUid);
    } else {
      m[otherUid] = v;
    }
    contactNames.value = m;
  }

  /// Mere liye dikhane wala naam: mera save kiya hua naam > uska nickname > username
  String displayName(
      String uid,
      Map<String, dynamic>? user, {
        String fallback = '',
      }) {
    final saved = (contactNames.value[uid] ?? '').trim();
    if (saved.isNotEmpty) return saved;
    final nick = ((user?['name'] as String?) ?? '').trim();
    if (nick.isNotEmpty) return nick;
    final un = ((user?['username'] as String?) ?? '').trim();
    return un.isNotEmpty ? un : fallback;
  }

  /// Meri online / last seen halat likho
  Future<void> setPresence(bool online) {
    return _db.collection('users').doc(_uid).set({
      'online': online,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Apna online / last seen dusron se chhupao ya dikhao
  Future<void> setHidePresence(bool hide) async {
    await _db.collection('users').doc(_uid).update({'hidePresence': hide});
    // cache purana na rahe, warna profile screen galat value dikhayegi
    final c = _userCache[_uid];
    if (c != null) _userCache[_uid] = {...c, 'hidePresence': hide};
  }

  /// Meri profile photo badlo ('' = hata do)
  Future<void> setMyPhoto(String url) async {
    await _db.collection('users').doc(_uid).update({'photoUrl': url});
    final c = _userCache[_uid];
    if (c != null) _userCache[_uid] = {...c, 'photoUrl': url};
  }

  /// Mera typing status is chat mein likho / hatao
  Future<void> setTyping(String chatId, bool typing) {
    return _db.collection('chats').doc(chatId).update({
      'typing.$_uid':
      typing ? FieldValue.serverTimestamp() : FieldValue.delete(),
    });
  }

  /// Kisi user ke document ko live sunne ke liye (online / last seen)
  Stream<DocumentSnapshot<Map<String, dynamic>>> userStream(String uid) {
    return _db.collection('users').doc(uid).snapshots();
  }
}