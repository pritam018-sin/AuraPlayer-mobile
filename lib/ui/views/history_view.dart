import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../player/player_models.dart';
import '../../services/thumbnail_service.dart';
import '../../state/player_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/frosted_glass.dart';

class HistoryView extends ConsumerStatefulWidget {
  const HistoryView({super.key});

  @override
  ConsumerState<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends ConsumerState<HistoryView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final textPrimary = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final borderCol = isDark ? AppTheme.glassBorder : AppTheme.lightGlassBorder;
    final cardBg = isDark
        ? const Color(0xFF131522).withValues(alpha: 0.35)
        : Colors.white.withValues(alpha: 0.45);

    final storage = ref.watch(storageServiceProvider);
    final recents = storage.getRecentFiles();

    final query = _searchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? recents
        : recents.where((item) => item.title.toLowerCase().contains(query)).toList();

    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 650;

    return Container(
      color: Colors.transparent,
      child: Column(
        children: [
          // Mobile Responsive History Toolbar
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 14 : 28,
              vertical: isMobile ? 12 : 16,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.surface.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.38),
              border: Border(
                bottom: BorderSide(color: borderCol, width: 0.5),
              ),
            ),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top Row: Title + Clear Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  gradient: AppTheme.auraGradient,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Icon(Icons.history_rounded, size: 18, color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Watch History',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: textPrimary,
                                    ),
                                  ),
                                  Text(
                                    '${recents.length} played media files',
                                    style: TextStyle(fontSize: 11, color: textSecondary),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (recents.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: () async {
                                await storage.clearRecentFiles();
                                setState(() {});
                              },
                              icon: const Icon(Icons.delete_outline_rounded, size: 14, color: Color(0xFFF43F5E)),
                              label: const Text('Clear All', style: TextStyle(color: Color(0xFFF43F5E), fontSize: 11.5)),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: const Color(0xFFF43F5E).withValues(alpha: 0.5)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Full Width Search Field on Mobile
                      Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: borderCol),
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(fontSize: 13, color: textPrimary),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Search history...',
                            hintStyle: TextStyle(
                              color: textSecondary.withValues(alpha: 0.7),
                              fontSize: 13,
                            ),
                            prefixIcon: Icon(Icons.search_rounded, size: 16, color: textSecondary),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.cancel_rounded, size: 15, color: textSecondary),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 9),
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              gradient: AppTheme.auraGradient,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.accent.withValues(alpha: 0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(Icons.history_rounded, size: 20, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Watch History',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${recents.length} recently played media files',
                                style: TextStyle(fontSize: 12, color: textSecondary),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          // Search bar
                          Container(
                            width: 240,
                            height: 36,
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: borderCol),
                            ),
                            child: TextField(
                              controller: _searchController,
                              style: TextStyle(fontSize: 13, color: textPrimary),
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: 'Search history...',
                                hintStyle: TextStyle(
                                  color: textSecondary.withValues(alpha: 0.7),
                                  fontSize: 13,
                                ),
                                prefixIcon: Icon(Icons.search_rounded, size: 16, color: textSecondary),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(Icons.cancel_rounded, size: 15, color: textSecondary),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {});
                                        },
                                      )
                                    : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (recents.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: () async {
                                await storage.clearRecentFiles();
                                setState(() {});
                              },
                              icon: const Icon(Icons.delete_outline_rounded, size: 15),
                              label: const Text('Clear History'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: textSecondary,
                                side: BorderSide(color: borderCol),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
          ),

          // Recents List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cardBg,
                            border: Border.all(color: borderCol),
                          ),
                          child: Center(
                            child: Icon(Icons.history_rounded, size: 32, color: textSecondary),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          query.isNotEmpty ? 'No Matching History' : 'No Watch History Yet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            query.isNotEmpty
                                ? 'Try searching with another keyword'
                                : 'Videos you play will automatically appear here with saved progress so you can resume anytime.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: textSecondary),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 12 : 28,
                      vertical: 12,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final thumb = ThumbnailService.getCachedThumbnail(item.path);
                      final progress = item.duration.inMilliseconds > 0
                          ? (item.position.inMilliseconds / item.duration.inMilliseconds).clamp(0.0, 1.0)
                          : 0.0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: FrostedGlass(
                          borderRadius: 14,
                          padding: EdgeInsets.all(isMobile ? 10 : 14),
                          fillColor: cardBg,
                          borderColor: borderCol,
                          blur: 35,
                          onTap: () {
                            ref.read(playlistProvider.notifier).setList([
                              PlaylistItem(path: item.path, title: item.title),
                            ]);
                          },
                          child: Row(
                            children: [
                              // Video Thumbnail or Placeholder
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: isMobile ? 64 : 80,
                                  height: isMobile ? 44 : 52,
                                  color: isDark ? const Color(0xFF1E2232) : const Color(0xFFCBD5E1),
                                  child: thumb != null && thumb.existsSync()
                                      ? Image.file(thumb, fit: BoxFit.cover)
                                      : Center(
                                          child: Icon(
                                            Icons.movie_rounded,
                                            size: 24,
                                            color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
                                          ),
                                        ),
                                ),
                              ),
                              SizedBox(width: isMobile ? 12 : 16),

                              // Video Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: isMobile ? 13 : 14,
                                        fontWeight: FontWeight.w600,
                                        color: textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Last played ${DateFormat.yMMMd().format(item.lastPlayed)}'
                                      '${item.duration.inSeconds > 0 ? " • ${_formatDuration(item.duration)}" : ""}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 10.5, color: textSecondary),
                                    ),
                                    if (progress > 0.02) ...[
                                      const SizedBox(height: 5),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(2),
                                              child: LinearProgressIndicator(
                                                value: progress,
                                                minHeight: 2.5,
                                                backgroundColor: isDark ? Colors.white12 : Colors.black12,
                                                valueColor: AlwaysStoppedAnimation(
                                                  isDark ? AppTheme.accentCyan : const Color(0xFF0284C7),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${(progress * 100).toInt()}%',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w700,
                                              color: isDark ? AppTheme.accentCyan : const Color(0xFF0284C7),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),

                              // Play / Resume Button
                              IconButton(
                                tooltip: progress > 0.02 ? 'Resume' : 'Play',
                                icon: Icon(
                                  progress > 0.02 ? Icons.play_circle_fill_rounded : Icons.play_circle_outline_rounded,
                                  color: AppTheme.accent,
                                  size: isMobile ? 32 : 36,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  ref.read(playlistProvider.notifier).setList([
                                    PlaylistItem(path: item.path, title: item.title),
                                  ]);
                                },
                              ),
                              const SizedBox(width: 4),

                              // Remove from history
                              IconButton(
                                tooltip: 'Remove from history',
                                icon: Icon(Icons.close_rounded, size: 16, color: textSecondary.withValues(alpha: 0.6)),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () async {
                                  await storage.removeRecentFile(item.path);
                                  setState(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
