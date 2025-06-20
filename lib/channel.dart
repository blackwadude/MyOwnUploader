import 'package:flutter/services.dart';

class VideoChannel {
  static const _channel = MethodChannel('video_picker');

  /// Returns `{ path: <.mov>, thumbnail: <.png> }`
  static Future<Map<String, String>?> pickOrCapture() async {
    final res = await _channel.invokeMethod<dynamic>('pickVideo');
    if (res is Map) {
      return res.map((k, v) => MapEntry(k as String, v as String));
    }
    return null;
  }
}