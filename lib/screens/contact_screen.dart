import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../chat_repository.dart';
import '../theme.dart';
import '../widgets.dart';
import '../photo_viewer.dart';

/// Groups wali Firestore collection ka naam. Agar tumhare project mein
/// koi aur naam hai to sirf yahan badlo.
const String _groupsCollection = 'groups';

class ContactScreen extends StatefulWidget {
  final String uid;
  final String username;
  final String photoUrl;

  const ContactScreen({
    super.key,
    required this.uid,
    required this.username,
    required this.photoUrl,
  });

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  final String _myUid = FirebaseAuth.instance.currentUser!.uid;
  late final String _chatId = chatRepo.chatIdWith(widget.uid);

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream =
  chatRepo.userStream(widget.uid);
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _chatStream =
  chatRepo.chatDocStream(_chatId);
  late final Future<List<String>> _mediaFuture = _loadMedia();
  late final Future<List<Map<String, dynamic>>> _groupsFuture = _loadGroups();

  bool _busy = false;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ------------------------------------------------------------- data

  /// Is chat mein bheji gayi photos (naye pehle). Aakhri 300 messages dekhta hai.
  Future<List<String>> _loadMedia() async {
    try {
      final cut = await chatRepo.deletedAtFor(_chatId);
      final snap = await chatRepo.messagesStream(_chatId, limit: 300).first;
      final now = DateTime.now();
      final urls = <String>[];
      for (final d in snap.docs) {
        final m = d.data();
        if (m['type'] != 'image') continue;
        final url = m['imageUrl'];
        if (url is! String || url.isEmpty) continue;
        if (m['deletedForAll'] == true) continue;
        final delFor = m['deletedFor'];
        if (delFor is List && delFor.contains(_myUid)) continue;
        final exp = m['expiresAt'];
        if (exp is Timestamp && exp.toDate().isBefore(now)) continue;
        final at = m['createdAt'];
        if (cut != null && at is Timestamp && at.compareTo(cut) <= 0) continue;
        urls.add(url);
      }
      return urls;
    } catch (e) {
      debugPrint('CONTACT MEDIA ERROR: $e');
      return [];
    }
  }

  /// Wo groups jin mein main aur ye contact dono maujood hain
  Future<List<Map<String, dynamic>>> _loadGroups() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_groupsCollection)
          .where('members', arrayContains: _myUid)
          .get();
      return snap.docs.where((d) {
        final m = d.data()['members'];
        return m is List && m.contains(widget.uid);
      }).map((d) => d.data()).toList();
    } catch (e) {
      debugPrint('COMMON GROUPS ERROR: $e');
      return [];
    }
  }

  // -------------------------------------------------------- last seen

  String _presenceText(Map<String, dynamic>? u, bool blocked) {
    if (blocked || u == null || u['hidePresence'] == true) return '';
    final seen = (u['lastSeen'] as Timestamp?)?.toDate();
    final online = u['online'] == true &&
        seen != null &&
        DateTime.now().difference(seen).inSeconds < 90;
    if (online) return 'online';
    if (seen == null) return '';

    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(seen.year, seen.month, seen.day);
    final diff = today.difference(day).inDays;
    final h = seen.hour % 12 == 0 ? 12 : seen.hour % 12;
    final time = '$h:${two(seen.minute)} ${seen.hour < 12 ? 'AM' : 'PM'}';
    if (diff == 0) return 'last seen today at $time';
    if (diff == 1) return 'last seen yesterday at $time';
    return 'last seen ${two(seen.day)}/${two(seen.month)}/${two(seen.year % 100)}';
  }

  // ---------------------------------------------------------- actions

  Future<void> _editSavedName(String current, String shownName) async {
    final c = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cream,
        title: const Text(
          'Contact name',
          style: TextStyle(
            color: AppColors.brown900,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: c,
              autofocus: true,
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(hintText: shownName),
            ),
            const Text(
              'Only you can see this name. Leave it empty to remove it.',
              style: TextStyle(fontSize: 12.5, color: AppColors.brown700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.brown700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Save',
                style: TextStyle(
                    color: AppColors.gold700, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (result == null || result == current) return;
    try {
      await chatRepo.setContactName(widget.uid, result);
      _snack(result.isEmpty ? 'Name removed.' : 'Name saved.');
    } catch (e) {
      debugPrint('SAVE CONTACT NAME ERROR: $e');
      _snack('Could not save the name. Try again.');
    }
  }

  Future<void> _toggleBlock(bool blockedByMe, String name) async {
    if (_busy) return;
    final block = !blockedByMe;

    if (block) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: softCardColor,
          title: Text(
            'Block $name?',
            style: const TextStyle(
              color: AppColors.brown900,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: const Text(
            'Blocked users cannot message you, and you cannot message them until you unblock.',
            style: TextStyle(color: AppColors.brown700),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busy = true);
    try {
      await chatRepo.setBlocked(_chatId, block);
      _snack(block ? 'User blocked' : 'User unblocked');
    } catch (e) {
      debugPrint('BLOCK ERROR: $e');
      _snack('Could not update block. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openMediaGrid(List<String> urls, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MediaGridScreen(urls: urls, title: title),
      ),
    );
  }

  // --------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Column(
        children: [
          const GradientHeader(
            title: 'Contact info',
            titleStyle: TextStyle(fontSize: 18, color: Colors.black),
            showBack: true,
          ),
          Expanded(
            child: ValueListenableBuilder<Map<String, String>>(
              valueListenable: chatRepo.contactNames,
              builder: (context, names, _) =>
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _userStream,
                    builder: (context, userSnap) =>
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: _chatStream,
                          builder: (context, chatSnap) =>
                              _body(names, userSnap.data?.data(), chatSnap.data),
                        ),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(
      Map<String, String> names,
      Map<String, dynamic>? liveUser,
      DocumentSnapshot<Map<String, dynamic>>? chatDoc,
      ) {
    final user = liveUser ?? chatRepo.cachedUser(widget.uid);
    final chat = chatDoc?.data();
    final chatExists = chatDoc?.exists == true;
    final bl = chat?['blockedBy'];
    final blockedByMe = bl is List && bl.contains(_myUid);
    final blockedByOther = bl is List && bl.contains(widget.uid);

    final liveUsername = ((user?['username'] as String?) ?? '').trim();
    final username = liveUsername.isNotEmpty ? liveUsername : widget.username;
    final nickname = ((user?['name'] as String?) ?? '').trim();
    final saved = (names[widget.uid] ?? '').trim();
    final about = ((user?['bio'] as String?) ??
        (user?['about'] as String?) ??
        '')
        .trim();
    final photo = (user?['photoUrl'] as String?) ?? widget.photoUrl;

    final shownName =
    chatRepo.displayName(widget.uid, user, fallback: widget.username);
    final status = _presenceText(user, blockedByMe || blockedByOther);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
      children: [
        Center(
          child: GestureDetector(
            onTap: photo.isEmpty
                ? null
                : () => openFullPhoto(
              context,
              title: shownName,
              photoUrl: photo,
            ),
            child: UserAvatar(username: shownName, photoUrl: photo, size: 120),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            shownName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.brown900,
            ),
          ),
        ),
        if (status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: status == 'online'
                      ? FontWeight.w700
                      : FontWeight.w400,
                  color: status == 'online'
                      ? AppColors.gold700
                      : AppColors.brown700,
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),

        // ---- mera save kiya hua naam
        _tile(
          icon: Icons.bookmark_border,
          label: 'Contact name',
          value: saved.isEmpty ? 'Add a name only you can see' : saved,
          muted: saved.isEmpty,
          trailing: const Icon(Icons.edit_outlined,
              size: 20, color: AppColors.gold700),
          onTap: () => _editSavedName(saved, shownName),
        ),

        // ---- info
        if (nickname.isNotEmpty)
          _tile(icon: Icons.person_outline, label: 'Name', value: nickname),
        if (username.isNotEmpty)
          _tile(
              icon: Icons.alternate_email, label: 'Username', value: username),
        if (about.isNotEmpty)
          _tile(icon: Icons.info_outline, label: 'About', value: about),

        // ---- media
        FutureBuilder<List<String>>(
          future: _mediaFuture,
          builder: (context, snap) {
            final urls = snap.data ?? const <String>[];
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox.shrink();
            }
            return _mediaSection(urls, shownName);
          },
        ),

        // ---- groups in common
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _groupsFuture,
          builder: (context, snap) {
            final groups = snap.data ?? const <Map<String, dynamic>>[];
            if (groups.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('GROUPS IN COMMON (${groups.length})'),
                for (final g in groups) _groupTile(g),
              ],
            );
          },
        ),

        // ---- block (chat maujood ho tabhi)
        if (chatExists) ...[
          const SizedBox(height: 8),
          _tile(
            icon: blockedByMe ? Icons.check_circle_outline : Icons.block,
            label: '',
            value: blockedByMe ? 'Unblock $shownName' : 'Block $shownName',
            danger: !blockedByMe,
            onTap: () => _toggleBlock(blockedByMe, shownName),
          ),
        ],
      ],
    );
  }

  Widget _sectionTitle(String text, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 16, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800,
                color: AppColors.gold700,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _mediaSection(List<String> urls, String shownName) {
    if (urls.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('MEDIA'),
          _tile(
            icon: Icons.photo_library_outlined,
            label: '',
            value: 'No media shared yet',
            muted: true,
          ),
        ],
      );
    }
    final preview = urls.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'MEDIA (${urls.length})',
          trailing: GestureDetector(
            onTap: () => _openMediaGrid(urls, shownName),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'See all',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.gold700,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: preview.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => openFullPhoto(
                context,
                title: shownName,
                photoUrl: preview[i],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: CachedNetworkImage(
                    imageUrl: preview[i],
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: AppColors.gold200),
                    errorWidget: (_, __, ___) => Container(
                      color: AppColors.gold200,
                      child: const Icon(Icons.broken_image_outlined,
                          color: AppColors.brown700),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _groupTile(Map<String, dynamic> g) {
    final name = ((g['name'] as String?) ?? '').trim();
    final photo = (g['photoUrl'] as String?) ?? '';
    final count = g['members'] is List ? (g['members'] as List).length : 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          UserAvatar(
              username: name.isEmpty ? 'Group' : name,
              photoUrl: photo,
              size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Group' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brown900,
                  ),
                ),
                if (count > 0)
                  Text(
                    '$count members',
                    style: const TextStyle(color: AppColors.brown700),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: softCardColor,
    borderRadius: BorderRadius.circular(18),
    boxShadow: [
      BoxShadow(
        color: AppColors.brown900.withValues(alpha: 0.08),
        blurRadius: 16,
        offset: const Offset(0, 5),
      ),
    ],
  );

  Widget _tile({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
    Widget? trailing,
    bool muted = false,
    bool danger = false,
  }) {
    final iconColor = danger ? Colors.red : AppColors.gold700;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _cardDecoration(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: iconColor),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (label.isNotEmpty) ...[
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brown700,
                          ),
                        ),
                        const SizedBox(height: 3),
                      ],
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                          muted ? FontWeight.w500 : FontWeight.w700,
                          color: danger
                              ? Colors.red
                              : (muted
                              ? AppColors.brown700
                              : AppColors.brown900),
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Saari shared photos ek grid mein
class _MediaGridScreen extends StatelessWidget {
  final List<String> urls;
  final String title;

  const _MediaGridScreen({required this.urls, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Column(
        children: [
          const GradientHeader(
            title: 'Media',
            titleStyle: TextStyle(fontSize: 18, color: Colors.black),
            showBack: true,
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: urls.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => openFullPhoto(
                  context,
                  title: title,
                  photoUrl: urls[i],
                ),
                child: CachedNetworkImage(
                  imageUrl: urls[i],
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: AppColors.gold200),
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.gold200,
                    child: const Icon(Icons.broken_image_outlined,
                        color: AppColors.brown700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}