import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativePlayerBridge {
  static const MethodChannel _channel = MethodChannel('com.aurastudio.auraplayer/storage');

  static final ValueNotifier<bool> isNativePipNotifier = ValueNotifier<bool>(false);
  static VoidCallback? onAudioBecomingNoisyCallback;

  static bool _initialized = false;

  static void init({VoidCallback? onAudioBecomingNoisy}) {
    if (!Platform.isAndroid || _initialized) return;
    _initialized = true;
    if (onAudioBecomingNoisy != null) {
      onAudioBecomingNoisyCallback = onAudioBecomingNoisy;
    }

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPipModeChanged':
          final isInPip = call.arguments as bool? ?? false;
          isNativePipNotifier.value = isInPip;
          break;
        case 'onAudioBecomingNoisy':
          onAudioBecomingNoisyCallback?.call();
          break;
      }
    });
  }

  static Future<void> enterPip({int num = 16, int den = 9}) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('enterPip', {
        'num': num,
        'den': den,
      });
    } catch (_) {}
  }

  static Future<void> setPlaybackActive({required bool isPlaying, String title = ''}) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setPlaybackActive', {
        'isPlaying': isPlaying,
        'title': title,
      });
    } catch (_) {}
  }

  static Future<String?> saveSnapshotToGallery({required String tempPath, required String title}) async {
    if (!Platform.isAndroid) return tempPath;
    try {
      final res = await _channel.invokeMethod<String>('saveSnapshotToGallery', {
        'tempPath': tempPath,
        'title': title,
      });
      return res ?? tempPath;
    } catch (_) {
      return tempPath;
    }
  }

  static Future<void> setScreenBrightness(double brightness) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setScreenBrightness', {'brightness': brightness});
    } catch (_) {}
  }

  static Future<double> getScreenBrightness() async {
    if (!Platform.isAndroid) return 0.5;
    try {
      final res = await _channel.invokeMethod<double>('getScreenBrightness');
      return res ?? 0.5;
    } catch (_) {
      return 0.5;
    }
  }

  static Future<void> resetScreenBrightness() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('resetScreenBrightness');
    } catch (_) {}
  }

  static Future<double> getSystemVolume() async {
    if (!Platform.isAndroid) return 100.0;
    try {
      final res = await _channel.invokeMethod<double>('getSystemVolume');
      return res ?? 100.0;
    } catch (_) {
      return 100.0;
    }
  }

  static Future<void> setSystemVolume(double percent) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setSystemVolume', {'percent': percent});
    } catch (_) {}
  }

  static Future<void> openCastSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openCastSettings');
    } catch (_) {}
  }

  static Future<void> castMediaToApp({required String url, String title = '', String mimeType = 'video/*'}) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('castMediaToApp', {
        'url': url,
        'title': title,
        'mimeType': mimeType,
      });
    } catch (_) {}
  }
}
