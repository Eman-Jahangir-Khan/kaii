import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

/// Photo poori screen par (zoom ke saath). Photo na ho to kuch nahi hota.
void openFullPhoto(
    BuildContext context, {
      required String title,
      required String photoUrl,
    }) {
  if (photoUrl.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
        body: Center(
          child: InteractiveViewer(
            child: CachedNetworkImage(
              imageUrl: photoUrl,
              fit: BoxFit.contain,
              placeholder: (_, __) => const CircularProgressIndicator(
                color: AppColors.gold700,
              ),
              errorWidget: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// WhatsApp jaisa chhota card: photo, naam, neeche message / call / info.
/// Photo par tap se poori screen wali photo khulti hai.
void showPhotoCard(
    BuildContext context, {
      required String name,
      required String photoUrl,
      required VoidCallback onMessage,
      VoidCallback? onInfo, // null ho to info icon nahi dikhta
      VoidCallback? onCall, // null ho to voice call icon nahi dikhta
      VoidCallback? onVideoCall, // null ho to video call icon nahi dikhta
      bool showCall = true, // purana parameter, ab use nahi hota (compile ke liye rakha hai)
    }) {
  final size = MediaQuery.of(context).size.width * 0.75;

  showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: size,
            color: softCardColor,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: photoUrl.isEmpty
                      ? null
                      : () => openFullPhoto(
                    context,
                    title: name,
                    photoUrl: photoUrl,
                  ),
                  child: Stack(
                    children: [
                      SizedBox(
                        width: size,
                        height: size,
                        child: photoUrl.isEmpty
                            ? Container(
                          color: AppColors.gold500.withValues(alpha: 0.2),
                          alignment: Alignment.center,
                          child: UserAvatar(
                            username: name,
                            photoUrl: '',
                            size: size * 0.5,
                          ),
                        )
                            : CachedNetworkImage(
                          imageUrl: photoUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.gold700,
                            ),
                          ),
                          errorWidget: (_, __, ___) =>
                          const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.black54, Colors.transparent],
                            ),
                          ),
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      tooltip: 'Message',
                      icon: const Icon(Icons.chat_bubble_outline,
                          color: AppColors.gold700),
                      onPressed: () {
                        Navigator.pop(ctx);
                        onMessage();
                      },
                    ),
                    if (onCall != null)
                      IconButton(
                        tooltip: 'Voice call',
                        icon: const Icon(Icons.call_outlined,
                            color: AppColors.gold700),
                        onPressed: () {
                          Navigator.pop(ctx);
                          onCall();
                        },
                      ),
                    if (onVideoCall != null)
                      IconButton(
                        tooltip: 'Video call',
                        icon: const Icon(Icons.videocam_outlined,
                            color: AppColors.gold700),
                        onPressed: () {
                          Navigator.pop(ctx);
                          onVideoCall();
                        },
                      ),
                    if (onInfo != null)
                      IconButton(
                        tooltip: 'Info',
                        icon: const Icon(Icons.info_outline,
                            color: AppColors.gold700),
                        onPressed: () {
                          Navigator.pop(ctx);
                          onInfo();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}