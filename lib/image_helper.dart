import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import 'theme.dart';

/// Photo chuno aur 1:1 crop karwao. User cancel kare to null.
Future<String?> pickSquareImage({
  ImageSource source = ImageSource.gallery,
}) async {
  final picked = await ImagePicker().pickImage(
    source: source,
    imageQuality: 85,
    maxWidth: 1600,
  );
  if (picked == null) return null;

  final cropped = await ImageCropper().cropImage(
    sourcePath: picked.path,
    aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
    compressQuality: 80,
    maxWidth: 800,
    maxHeight: 800,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: 'Crop photo',
        toolbarColor: AppColors.gold700,
        toolbarWidgetColor: Colors.white,
        activeControlsWidgetColor: AppColors.gold700,
        lockAspectRatio: true,
      ),
      IOSUiSettings(
        title: 'Crop photo',
        aspectRatioLockEnabled: true,
        resetAspectRatioEnabled: false,
        aspectRatioPickerButtonHidden: true,
      ),
    ],
  );
  return cropped?.path;
}