import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Poori app mein yehi ek instance use hoga
final statusRepo = StatusRepository();

/// Status kitni der rehta hai
const statusLifetime = Duration(hours: 24);

/// Video ke sirf pehle [seconds] seconds chalen (Cloudinary delivery transformation)
String trimVideoUrl(String url, int seconds) =>
    url.replaceFirst('/upload/', '/upload/so_0,eo_$seconds/');


/// Status ki default visibility
class StatusPrivacy {
  final String mode; // 'contacts' | 'only' | 'except'
  final List<String> uids;
  const StatusPrivacy(this.mode, this.uids);
}

/// Ek status (image ya video)
class StatusItem {
  final String id;
  final String ownerId;
  final String mediaUrl;
  final String mediaType; // 'image' ya 'video'
  final String caption;
  final int? width;
  final int? height;
  final DateTime? createdAt; // server timestamp aane tak null ho sakta hai
  final int? bgColor; // sirf text status ke liye
  final int fontIdx; // text status ka font
  final DateTime expiresAt;
  final List<String> visibleTo;
  final List<String> likes;
  final List<String> viewedBy;

  const StatusItem({
    required this.id,
    required this.ownerId,
    required this.mediaUrl,
    required this.mediaType,
    required this.caption,
    required this.expiresAt,
    required this.visibleTo,
    required this.likes,
    required this.viewedBy,
    this.width,
    this.height,
    this.createdAt,
    this.bgColor,
    this.fontIdx = 0,
  });

  bool get isVideo => mediaType == 'video';
  bool get isText => mediaType == 'text';
  bool get isExpired => !expiresAt.isAfter(DateTime.now());
  bool likedBy(String uid) => likes.contains(uid);
  bool viewedByMe(String uid) => viewedBy.contains(uid);

  factory StatusItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return StatusItem(
      id: d.id,
      ownerId: m['ownerId'] as String? ?? '',
      mediaUrl: m['mediaUrl'] as String? ?? '',
      mediaType: m['mediaType'] as String? ?? 'image',
      caption: m['caption'] as String? ?? '',
      width: m['width'] as int?,
      height: m['height'] as int?,
      bgColor: (m['bgColor'] as num?)?.toInt(),
      fontIdx: (m['fontIdx'] as num?)?.toInt() ?? 0,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      expiresAt: (m['expiresAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      visibleTo: List<String>.from(m['visibleTo'] as List? ?? const []),
      likes: List<String>.from(m['likes'] as List? ?? const []),
      viewedBy: List<String>.from(m['viewedBy'] as List? ?? const []),
    );
  }
}

class StatusRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('statuses');

  /// Mere "added" contacts ke uids: accepted chats, jin mein koi block na ho.
  /// (Purani chats jin mein status field nahi, accepted maani jati hain.)
  Future<List<String>> contactUids() async {
    final snap = await _db
        .collection('chats')
        .where('participants', arrayContains: _uid)
        .get();

    final out = <String>[];
    for (final d in snap.docs) {
      final m = d.data();
      final s = m['status'] as String?;
      if (s != null && s != 'accepted') continue;

      final blockedBy = m['blockedBy'];
      if (blockedBy is List && blockedBy.isNotEmpty) continue; // kisi ne bhi block kiya ho

      final parts = List<String>.from(m['participants'] as List);
      final other = parts.firstWhere((u) => u != _uid, orElse: () => '');
      if (other.isNotEmpty) out.add(other);
    }
    return out;
  }

  Future<StatusPrivacy> getPrivacy() async {
    final d = await _db.collection('statusSettings').doc(_uid).get();
    final m = d.data();
    if (m == null) return const StatusPrivacy('contacts', []);
    return StatusPrivacy(
      (m['mode'] as String?) ?? 'contacts',
      List<String>.from(m['uids'] as List? ?? const []),
    );
  }

  Future<void> savePrivacy(String mode, List<String> uids) {
    return _db.collection('statusSettings').doc(_uid).set({
      'mode': mode,
      'uids': uids,
    });
  }

  /// Naya status lagao. visibleTo = wo uids jo isay dekh sakte hain.
  Future<void> post({
    String mediaUrl = '',
    required String mediaType, // 'image' | 'video' | 'text'
    required List<String> visibleTo,
    String caption = '',
    int? width,
    int? height,
    int? bgColor,
    int? fontIdx,
  }) {
    return _col.add({
      'ownerId': _uid,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'caption': caption.trim(),
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (bgColor != null) 'bgColor': bgColor,
      if (fontIdx != null) 'fontIdx': fontIdx,
      'visibleTo': visibleTo.where((u) => u != _uid).toList(),
      'likes': <String>[],
      'viewedBy': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(statusLifetime)),
    });
  }

  /// Dusron ke wo statuses jo mujhe dikhne chahiyen (24 ghante ke andar)
  /// Dusron ke wo statuses jo mujhe dikhne chahiye (24 ghante ke andar)
  Stream<List<StatusItem>> feedStream() {
    return _col
        .where('visibleTo', arrayContains: _uid)
        .snapshots()
        .map(_activeOnly);
  }

  /// Mere apne statuses
  Stream<List<StatusItem>> myStream() {
    return _col
        .where('ownerId', isEqualTo: _uid)
        .snapshots()
        .map(_activeOnly);
  }

  List<StatusItem> _activeOnly(QuerySnapshot<Map<String, dynamic>> s) =>
      s.docs.map(StatusItem.fromDoc).where((i) => !i.isExpired).toList();

  Future<void> delete(String statusId) => _col.doc(statusId).delete();

  // ---------------- likes ----------------

  Future<void> setLike(String statusId, bool liked) {
    return _col.doc(statusId).update({
      'likes': liked
          ? FieldValue.arrayUnion([_uid])
          : FieldValue.arrayRemove([_uid]),
    });
  }

  // ---------------- comments ----------------

  Stream<QuerySnapshot<Map<String, dynamic>>> commentsStream(String statusId) {
    return _col
        .doc(statusId)
        .collection('comments')
        .orderBy('createdAt')
        .snapshots();
  }

  Future<void> addComment(String statusId, String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await _col.doc(statusId).collection('comments').add({
      'userId': _uid,
      'text': t,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------- views ("seen by") ----------------

  /// Dusre ka status dekha to likh do (apna status dekhne par call na karna)
  Future<void> markViewed(String statusId) {
    final ref = _col.doc(statusId);
    final batch = _db.batch();
    batch.set(ref.collection('views').doc(_uid), {
      'viewedAt': FieldValue.serverTimestamp(),
    });
    batch.update(ref, {
      'viewedBy': FieldValue.arrayUnion([_uid]),
    });
    return batch.commit();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> viewsStream(String statusId) {
    return _col.doc(statusId).collection('views').snapshots();
  }

  /// Status abhi dekha ja sakta hai? (expire/delete/hidden ho to null)
  Future<StatusItem?> getActive(String statusId) async {
    try {
      final d = await _col.doc(statusId).get();
      if (!d.exists) return null;
      final item = StatusItem.fromDoc(d);
      if (item.isExpired) return null;
      if (item.ownerId != _uid && !item.visibleTo.contains(_uid)) return null;
      return item;
    } catch (_) {
      return null; // rules ne rok diya = ab nahi dekh sakti
    }
  }
}