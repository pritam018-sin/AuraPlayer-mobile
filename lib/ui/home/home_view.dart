import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../player/player_models.dart';
import '../../state/player_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/frosted_glass.dart';
import '../modals/open_network_modal.dart';

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mkv', 'avi', 'webm', 'mov', 'flv', 'wmv', 'ts', 'm4v'],
      allowMultiple: true,
    );

    if (result != null && result.paths.isNotEmpty) {
      final items = result.paths
          .whereType<String>()
          .map((p) => PlaylistItem(
                path: p,
                title: p.split(RegExp(r'[/\\]')).last,
              ))
          .toList();

      if (items.isNotEmpty) {
        ref.read(playlistProvider.notifier).setList(items, initialIndex: 0);
      }
    }
  }

  Future<void> _openFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null) {
      final dir = Directory(path);
      final videoExts = ['.mp4', '.mkv', '.avi', '.webm', '.mov', '.flv', '.wmv'];
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => videoExts.any((ext) => f.path.toLowerCase().endsWith(ext)))
          .map((f) => PlaylistItem(path: f.path, title: f.path.split(RegExp(r'[/\\]')).last))
          .toList();

      if (files.isNotEmpty) {
        ref.read(playlistProvider.notifier).setList(files, initialIndex: 0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(storageServiceProvider);
    final recents = storage.getRecentFiles();
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final textPrimary = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final glassBorder = isDark ? AppTheme.glassBorder : AppTheme.lightGlassBorder;
    final cardBg = isDark
        ? const Color(0xFF10121A).withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.35);

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Container(
      color: Colors.transparent,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 40,
            vertical: isMobile ? 20 : 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drop Zone Card with true Frosted Glass
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    width: isMobile ? double.infinity : 640,
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 20 : 48,
                      vertical: isMobile ? 28 : 48,
                    ),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: glassBorder,
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.08),
                          blurRadius: 32,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: glassBorder,
                        ),
                      ),
                      child: const Icon(
                        Icons.play_circle_fill_rounded,
                        size: 38,
                        color: AppTheme.accentHover,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Tap to Open Video File',
                      style: AppTheme.headline.copyWith(color: textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Supports MP4, MKV, AVI, WebM, MOV, and more',
                      style: AppTheme.caption.copyWith(color: textSecondary),
                    ),
                      const SizedBox(height: 28),

                      // Action Buttons Row
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pickFiles,
                            icon: const Icon(Icons.video_file_rounded, size: 17),
                            label: const Text('Open Video File'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              foregroundColor: const Color(0xFF04131F),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                              textStyle: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _openFolder,
                            icon: const Icon(Icons.folder_rounded, size: 17),
                            label: const Text('Open Folder'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: textPrimary,
                              side: BorderSide(color: glassBorder),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              textStyle: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w500, color: textPrimary),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => OpenNetworkModal.show(context),
                            icon: const Icon(Icons.public_rounded, size: 17),
                            label: const Text('Network Stream'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: textPrimary,
                              side: BorderSide(color: glassBorder),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              textStyle: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w500, color: textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

                // Recent Files Section
                if (recents.isNotEmpty) ...[
                  const SizedBox(height: 44),
                  SizedBox(
                    width: 720,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Recent Videos',
                              style: AppTheme.body.copyWith(
                                fontWeight: FontWeight.w600,
                                color: textSecondary,
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                await storage.clearRecentFiles();
                                setState(() {});
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: textSecondary,
                                textStyle: AppTheme.caption,
                              ),
                              child: const Text('Clear All'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: recents.length > 5 ? 5 : recents.length,
                          separatorBuilder: (_, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = recents[index];
                            return _recentCard(item, isDark, textPrimary, textSecondary, glassBorder);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
  }

  Widget _recentCard(
    RecentItem item,
    bool isDark,
    Color textPrimary,
    Color textSecondary,
    Color glassBorder,
  ) {
    final progress = item.duration.inMilliseconds > 0
        ? (item.position.inMilliseconds / item.duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return FrostedGlass(
      borderRadius: 14,
      blur: 24,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      fillColor: isDark
          ? const Color(0xFF10121A).withValues(alpha: 0.18)
          : Colors.white.withValues(alpha: 0.35),
      borderColor: glassBorder,
      onTap: () {
        ref.read(playlistProvider.notifier).setList([
          PlaylistItem(path: item.path, title: item.title),
        ]);
      },
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: glassBorder),
            ),
            child: const Icon(
              Icons.movie_rounded,
              size: 20,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'Last watched ${DateFormat.yMMMd().format(item.lastPlayed)}',
                      style: AppTheme.caption.copyWith(color: textSecondary),
                    ),
                    if (progress > 0.02) ...[
                      const SizedBox(width: 8),
                      Text('•', style: AppTheme.caption.copyWith(color: textSecondary)),
                      const SizedBox(width: 8),
                      Text(
                        '${(progress * 100).toInt()}% completed',
                        style: AppTheme.caption.copyWith(color: AppTheme.accent),
                      ),
                    ],
                  ],
                ),
                if (progress > 0.02) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 2.5,
                      backgroundColor: isDark ? Colors.white12 : Colors.black12,
                      valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            Icons.play_arrow_rounded,
            size: 16,
            color: textSecondary,
          ),
        ],
      ),
    );
  }
}
