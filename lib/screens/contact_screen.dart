import 'package:flutter/material.dart';

import '../chat_repository.dart';
import '../theme.dart';
import '../widgets.dart';
import '../photo_viewer.dart';

class ContactScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Column(
        children: [
          GradientHeader(
            title: 'Contact info',
            titleStyle: const TextStyle(fontSize: 18, color: Colors.black),
            showBack: true,
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
              future: chatRepo.getUser(uid),
              initialData: chatRepo.cachedUser(uid),
              builder: (context, snap) {
                final user = snap.data;
                final name = ((user?['name'] as String?) ?? '').trim();
                final email = ((user?['email'] as String?) ?? '').trim();
                final bio = ((user?['bio'] as String?) ?? '').trim();

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: photoUrl.isEmpty
                            ? null
                            : () => openFullPhoto(
                          context,
                          title: username,
                          photoUrl: photoUrl,
                        ),
                        child: UserAvatar(
                          username: username,
                          photoUrl: photoUrl,
                          size: 120,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        username,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brown900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (name.isNotEmpty)
                      _infoTile(Icons.person_outline, 'Name', name),
                    if (email.isNotEmpty)
                      _infoTile(Icons.mail_outline, 'Email', email),
                    if (bio.isNotEmpty)
                      _infoTile(Icons.info_outline, 'About', bio),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: softCardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.brown900.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.gold700),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brown700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brown900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}