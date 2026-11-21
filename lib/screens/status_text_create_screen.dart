import 'package:flutter/material.dart';

import '../chat_repository.dart';
import '../status_repository.dart';
import '../theme.dart';
import '../widgets.dart';
import 'status_create_screen.dart' show ContactPicker;
import 'status_fonts.dart';

enum _Vis { contacts, only, except }

const _bgColors = <Color>[
  Color(0xFF6D4C41),
  Color(0xFFB8860B),
  Color(0xFF00695C),
  Color(0xFF3949AB),
  Color(0xFF6A1B9A),
  Color(0xFFC62828),
  Color(0xFF263238),
];

class CreateTextStatusScreen extends StatefulWidget {
  const CreateTextStatusScreen({super.key});

  @override
  State<CreateTextStatusScreen> createState() => _CreateTextStatusScreenState();
}

class _CreateTextStatusScreenState extends State<CreateTextStatusScreen> {
  final _text = TextEditingController();
  int _bgIdx = 0;
  int _fontIdx = 0;
  bool _loading = false;

  _Vis _vis = _Vis.contacts;
  List<Map<String, String>> _contacts = [];
  bool _contactsReady = false;
  Set<String> _picked = {};

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _loadDefaultPrivacy();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    try {
      final uids = await statusRepo.contactUids();
      final users = await Future.wait(uids.map((u) async {
        final d = await chatRepo.getUser(u);
        return <String, String>{
          'uid': u,
          'username': (d?['username'] as String?) ?? 'user',
          'photoUrl': (d?['photoUrl'] as String?) ?? '',
        };
      }));
      users.sort((a, b) => a['username']!.compareTo(b['username']!));
      if (!mounted) return;
      setState(() {
        _contacts = users;
        _contactsReady = true;
      });
    } catch (e) {
      debugPrint('load contacts error: $e');
      if (mounted) setState(() => _contactsReady = true);
    }
  }

  Future<void> _loadDefaultPrivacy() async {
    try {
      final p = await statusRepo.getPrivacy();
      if (!mounted) return;
      setState(() {
        _vis = switch (p.mode) {
          'only' => _Vis.only,
          'except' => _Vis.except,
          _ => _Vis.contacts,
        };
        _picked = p.uids.toSet();
      });
    } catch (e) {
      debugPrint('load default privacy error: $e');
    }
  }

  Future<void> _chooseContacts() async {
    final res = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ContactPicker(
        contacts: _contacts,
        initial: _picked,
        title: _vis == _Vis.only ? 'Share with' : 'Hide from',
      ),
    );
    if (res != null && mounted) setState(() => _picked = res);
  }

  Future<void> _post() async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    if (_text.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Write something first.')),
      );
      return;
    }
    if (_contacts.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Add some contacts first.')),
      );
      return;
    }
    if (_vis != _Vis.contacts && _picked.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Choose at least one contact.')),
      );
      return;
    }

    final all = _contacts.map((c) => c['uid']!).toList();
    final List<String> visibleTo;
    switch (_vis) {
      case _Vis.contacts:
        visibleTo = all;
      case _Vis.only:
        visibleTo = all.where(_picked.contains).toList();
      case _Vis.except:
        visibleTo = all.where((u) => !_picked.contains(u)).toList();
    }
    if (visibleTo.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nobody would be able to see this status.')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await statusRepo.post(
        mediaType: 'text',
        visibleTo: visibleTo,
        caption: _text.text,
        bgColor: _bgColors[_bgIdx].toARGB32(),
        fontIdx: _fontIdx,
      );
      nav.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Status posted')),
      );
    } catch (e, st) {
      debugPrint('post text status error: $e\n$st');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not post status. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _visTile(_Vis v, String title, String subtitle) {
    final selected = _vis == v;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => setState(() => _vis = v),
      leading: Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        color: selected ? AppColors.gold700 : AppColors.brown700,
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.brown900,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppColors.brown700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPost = !_loading && _contactsReady;

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Column(
        children: [
          const GradientHeader(title: 'Text status', showBack: true),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    height: 380,
                    width: double.infinity,
                    color: _bgColors[_bgIdx],
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: TextField(
                      controller: _text,
                      autofocus: true,
                      maxLength: 200,
                      maxLines: null,
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.sentences,
                      cursorColor: Colors.white,
                      style: statusFontStyle(_fontIdx, size: 26),
                      decoration: const InputDecoration(
                        hintText: 'Type a status',
                        hintStyle: TextStyle(color: Colors.white60),
                        border: InputBorder.none,
                        counterStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _bgColors.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => setState(() => _bgIdx = i),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _bgColors[i],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: i == _bgIdx
                                ? AppColors.brown900
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: statusFontNames.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final sel = i == _fontIdx;
                      return GestureDetector(
                        onTap: () => setState(() => _fontIdx = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: sel
                                ? AppColors.gold200
                                : Colors.white.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: sel
                                  ? AppColors.gold700
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Text(
                            statusFontNames[i],
                            style: statusFontStyle(i,
                                size: 16, color: AppColors.brown900),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Who can see this?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brown900,
                  ),
                ),
                const SizedBox(height: 4),
                _visTile(_Vis.contacts, 'My contacts', 'Everyone you have added'),
                _visTile(_Vis.only, 'Only share with...',
                    'Pick the contacts who can see it'),
                _visTile(_Vis.except, 'My contacts except...',
                    'Hide it from some contacts'),
                if (_vis != _Vis.contacts)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: OutlinedButton.icon(
                      onPressed: _contacts.isEmpty ? null : _chooseContacts,
                      icon: const Icon(Icons.people_alt_outlined),
                      label: Text(
                        _picked.isEmpty
                            ? 'Choose contacts'
                            : 'Choose contacts (${_picked.length})',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.gold700,
                        side: const BorderSide(color: AppColors.gold700),
                      ),
                    ),
                  ),
                if (_contactsReady && _contacts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'You have no contacts yet. Add someone from Chats first.',
                      style: TextStyle(color: AppColors.brown700),
                    ),
                  ),
                const SizedBox(height: 20),
                PillButton(
                  label: 'Post status',
                  loading: _loading,
                  onPressed: canPost ? _post : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}