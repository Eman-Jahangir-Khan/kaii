import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import 'theme.dart';

/// Chat / group chat mein attach karne par jo file chuni gayi.
class PickedMedia {
  final XFile file;
  final bool isVideo;
  const PickedMedia(this.file, this.isVideo);
}

const _videoExt = ['mp4', 'mov', 'm4v', '3gp', 'mkv', 'webm', 'avi'];

bool _looksLikeVideo(String path) =>
    _videoExt.contains(path.split('.').last.toLowerCase());

Future<String?> _sheet(
    BuildContext context,
    List<(String, IconData, String, String?)> items,
    ) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Wrap(
        children: [
          for (final (value, icon, title, subtitle) in items)
            ListTile(
              leading: Icon(icon),
              title: Text(title),
              subtitle: subtitle == null ? null : Text(subtitle),
              onTap: () => Navigator.pop(ctx, value),
            ),
        ],
      ),
    ),
  );
}

/// Attach sheet: sirf 2 options, Gallery (photo + video) aur Camera (photo + video).
/// Kuch na chune to null wapas aata hai.
Future<PickedMedia?> pickChatMedia(BuildContext context) async {
  final picker = ImagePicker();

  final choice = await _sheet(context, const [
    ('gallery', Icons.photo_library_outlined, 'Gallery', 'Photo or video'),
    ('camera', Icons.photo_camera_outlined, 'Camera', 'Photo or video'),
  ]);
  if (choice == null) return null;

  if (choice == 'gallery') return _pickFromGallery(context);

  // Camera: Android/iOS ka camera ek waqt mein photo ya video hi leta hai,
  // is liye yahan chhota sa doosra sawal
  if (!context.mounted) return null;
  final kind = await _sheet(context, const [
    ('photo', Icons.photo_camera_outlined, 'Take photo', null),
    ('video', Icons.videocam_outlined, 'Record video', null),
  ]);
  if (kind == null) return null;

  if (kind == 'photo') {
    final XFile? f = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1280,
    );
    return f == null ? null : PickedMedia(f, false);
  }

  final XFile? f = await picker.pickVideo(
    source: ImageSource.camera,
    maxDuration: const Duration(minutes: 1),
  );
  return f == null ? null : PickedMedia(f, true);
}

/// In-app gallery: sirf photos aur videos dikhte hain (file manager nahi)
Future<PickedMedia?> _pickFromGallery(BuildContext context) async {
  final assets = await AssetPicker.pickAssets(
    context,
    pickerConfig: AssetPickerConfig(
      maxAssets: 1,
      requestType: RequestType.common, // photo + video
      textDelegate: const EnglishAssetPickerTextDelegate(),
      pickerTheme: AssetPicker.themeData(AppColors.gold700, light: true),
    ),
  );
  if (assets == null || assets.isEmpty) return null;
  final a = assets.first;

  if (a.type == AssetType.video) {
    final f = await a.originFile;
    return f == null ? null : PickedMedia(XFile(f.path), true);
  }

  // photo: pehle jaisa compress (max 1280 px, quality 70)
  final bytes = await a.thumbnailDataWithSize(
    ThumbnailSize(1280, 1280),
    quality: 70,
  );
  if (bytes == null) return null;
  final tmp = File(
    '${Directory.systemTemp.path}/kaii_${DateTime.now().millisecondsSinceEpoch}.jpg',
  );
  await tmp.writeAsBytes(bytes);
  return PickedMedia(XFile(tmp.path), false);
}