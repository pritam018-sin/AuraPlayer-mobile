import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VideoFileItem {
  final String path;
  final String name;
  final String title;
  final String folderName;
  final int sizeBytes;
  final int dateModifiedMs;
  final int durationMs;
  final int width;
  final int height;
  final int mediaStoreId;

  const VideoFileItem({
    required this.path,
    required this.name,
    required this.title,
    required this.folderName,
    required this.sizeBytes,
    required this.dateModifiedMs,
    this.durationMs = 0,
    this.width = 0,
    this.height = 0,
    this.mediaStoreId = 0,
  });

  factory VideoFileItem.fromMap(Map<dynamic, dynamic> map) {
    final path = map['path'] as String? ?? '';
    final name = map['name'] as String? ?? (path.split(RegExp(r'[/\\]')).last);
    final title = map['title'] as String? ?? name;
    final folder = map['bucketName'] as String? ?? '';
    return VideoFileItem(
      path: path,
      name: name,
      title: title.isNotEmpty ? title : name,
      folderName: folder.isNotEmpty ? folder : 'Internal Storage',
      sizeBytes: (map['size'] as num?)?.toInt() ?? 0,
      dateModifiedMs: (map['dateModified'] as num?)?.toInt() ?? 0,
      durationMs: (map['duration'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      mediaStoreId: (map['id'] as num?)?.toInt() ?? 0,
    );
  }

  factory VideoFileItem.fromFile(File file) {
    final path = file.path;
    final name = path.split(RegExp(r'[/\\]')).last;
    final folderName = file.parent.path.split(RegExp(r'[/\\]')).last;
    int size = 0;
    int modified = 0;
    try {
      final stat = file.statSync();
      size = stat.size;
      modified = stat.modified.millisecondsSinceEpoch;
    } catch (_) {}

    return VideoFileItem(
      path: path,
      name: name,
      title: name,
      folderName: folderName.isEmpty ? 'Internal Storage' : folderName,
      sizeBytes: size,
      dateModifiedMs: modified,
    );
  }

  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot != -1 && dot < name.length - 1) {
      return name.substring(dot + 1).toUpperCase();
    }
    return 'VIDEO';
  }

  String get formattedDuration {
    if (durationMs <= 0) return '';
    final totalSec = durationMs ~/ 1000;
    final hrs = totalSec ~/ 3600;
    final mins = (totalSec % 3600) ~/ 60;
    final secs = totalSec % 60;
    if (hrs > 0) {
      return '$hrs:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  String get formattedSize {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    if (sizeBytes >= 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$sizeBytes B';
  }
}

class MobileStorageService {
  static const MethodChannel _channel = MethodChannel('com.aurastudio.auraplayer/storage');

  /// Check if All Files Access / Storage permission is granted on Android
  static Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final bool? granted = await _channel.invokeMethod<bool>('checkPermission');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Request All Files Access (opens system permission toggle)
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final bool? result = await _channel.invokeMethod<bool>('requestPermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Fast query all media videos from Android MediaStore (native SQLite database in 20ms)
  static Future<List<VideoFileItem>> queryMediaVideos() async {
    if (!Platform.isAndroid) return [];
    try {
      final List<dynamic>? list = await _channel.invokeMethod<List<dynamic>>('queryMediaVideos');
      if (list != null) {
        return list
            .whereType<Map<dynamic, dynamic>>()
            .map((m) => VideoFileItem.fromMap(m))
            .where((item) => item.path.isNotEmpty)
            .toList();
      }
    } catch (e) {
      debugPrint('queryMediaVideos error: $e');
    }
    return [];
  }

  /// Get storage roots on the device (/storage/emulated/0, SD cards)
  static Future<List<String>> getStorageRoots() async {
    if (!Platform.isAndroid) return [];
    try {
      final List<dynamic>? roots = await _channel.invokeMethod<List<dynamic>>('getStorageRoots');
      if (roots != null) {
        return roots.whereType<String>().toList();
      }
    } catch (_) {}
    return ['/storage/emulated/0'];
  }

  /// Recursively scan for video files safely, skipping hidden and system directories
  static List<File> scanDirectory(
    Directory dir, {
    required List<String> videoExtensions,
    int maxDepth = 4,
    int currentDepth = 0,
  }) {
    final List<File> result = [];
    if (currentDepth > maxDepth) return result;

    try {
      final entities = dir.listSync(recursive: false, followLinks: false);
      for (final entity in entities) {
        final name = entity.path.split(RegExp(r'[/\\]')).last;
        // Skip hidden folders and Android system private directories
        if (name.startsWith('.') || name.startsWith(r'$')) continue;

        if (entity is File) {
          final lower = entity.path.toLowerCase();
          if (videoExtensions.any((ext) => lower.endsWith(ext))) {
            result.add(entity);
          }
        } else if (entity is Directory) {
          if (name == 'Android' && currentDepth == 0) {
            final mediaDir = Directory('${entity.path}/media');
            if (mediaDir.existsSync()) {
              result.addAll(scanDirectory(
                mediaDir,
                videoExtensions: videoExtensions,
                maxDepth: maxDepth,
                currentDepth: currentDepth + 1,
              ));
            }
            continue;
          }
          if (name == 'data' || name == 'cache' || name == '.thumbnails') continue;

          result.addAll(scanDirectory(
            entity,
            videoExtensions: videoExtensions,
            maxDepth: maxDepth,
            currentDepth: currentDepth + 1,
          ));
        }
      }
    } catch (_) {}

    return result;
  }

  /// Scan directory in a background isolate so UI thread is NEVER blocked
  static Future<List<VideoFileItem>> scanDirectoryAsync(
    String folderPath, {
    required List<String> videoExtensions,
  }) async {
    return compute(_scanDirectoryIsolate, {
      'folderPath': folderPath,
      'extensions': videoExtensions,
    });
  }

  static List<VideoFileItem> _scanDirectoryIsolate(Map<String, dynamic> params) {
    final folderPath = params['folderPath'] as String;
    final extensions = params['extensions'] as List<String>;
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return [];

    final rawFiles = scanDirectory(dir, videoExtensions: extensions, maxDepth: 4);
    return rawFiles.map((f) => VideoFileItem.fromFile(f)).toList();
  }
}
