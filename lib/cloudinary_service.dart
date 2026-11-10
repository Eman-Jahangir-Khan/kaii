import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class CloudinaryService {
  static const _cloudName = 'a68euwrg';
  static const _preset = 'ml_default';

  /// Image upload karo, secure_url + size wapis do
  Future<Map<String, dynamic>> uploadImage(File file) async {
    final uri =
    Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');
    final req = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _preset
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final res = await http.Response.fromStream(
      await req.send().timeout(const Duration(seconds: 60)),
    );
    if (res.statusCode != 200) {
      throw Exception('Upload failed: ${res.body}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return {
      'url': j['secure_url'] as String,
      'width': j['width'],
      'height': j['height'],
    };
  }
}

final cloudinary = CloudinaryService();