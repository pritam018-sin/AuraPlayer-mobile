import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../player/player_controller.dart';
import '../../theme/app_theme.dart';

class SubtitleSearchResult {
  final String subFileName;
  final String languageName;
  final String langCode;
  final int downloadCount;
  final double rating;
  final String downloadLink;

  const SubtitleSearchResult({
    required this.subFileName,
    required this.languageName,
    required this.langCode,
    required this.downloadCount,
    required this.rating,
    required this.downloadLink,
  });

  factory SubtitleSearchResult.fromJson(Map<String, dynamic> json) {
    final ratingNum = double.tryParse(json['SubRating']?.toString() ?? '0') ?? 0.0;
    final downloads = int.tryParse(json['SubDownloadsCnt']?.toString() ?? '0') ?? 0;
    return SubtitleSearchResult(
      subFileName: json['SubFileName'] as String? ?? 'Subtitle.srt',
      languageName: json['LanguageName'] as String? ?? 'English',
      langCode: json['SubLanguageID'] as String? ?? 'eng',
      downloadCount: downloads,
      rating: ratingNum,
      downloadLink: json['SubDownloadLink'] as String? ?? '',
    );
  }
}

class OnlineSubtitlesModal extends StatefulWidget {
  final AuraPlayerWrapper playerWrapper;

  const OnlineSubtitlesModal({super.key, required this.playerWrapper});

  static Future<void> show(BuildContext context, AuraPlayerWrapper playerWrapper) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OnlineSubtitlesModal(playerWrapper: playerWrapper),
    );
  }

  @override
  State<OnlineSubtitlesModal> createState() => _OnlineSubtitlesModalState();
}

class _OnlineSubtitlesModalState extends State<OnlineSubtitlesModal> {
  final TextEditingController _queryController = TextEditingController();
  String _selectedLang = 'eng';
  bool _isSearching = false;
  String? _downloadingSubUrl;
  String? _errorMessage;
  List<SubtitleSearchResult> _results = [];

  final List<Map<String, String>> _languages = [
    {'code': 'eng', 'label': 'English'},
    {'code': 'hin', 'label': 'Hindi'},
    {'code': 'spa', 'label': 'Spanish'},
    {'code': 'fre', 'label': 'French'},
    {'code': 'ger', 'label': 'German'},
    {'code': 'jpn', 'label': 'Japanese'},
    {'code': 'ara', 'label': 'Arabic'},
    {'code': 'por', 'label': 'Portuguese'},
    {'code': 'all', 'label': 'All Languages'},
  ];

  @override
  void initState() {
    super.initState();
    _queryController.text = _cleanVideoTitle(widget.playerWrapper.currentTitle ?? '');
    if (_queryController.text.trim().isNotEmpty) {
      _performSearch();
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  String _cleanVideoTitle(String raw) {
    var title = raw.trim();
    // Remove extension
    final extDot = title.lastIndexOf('.');
    if (extDot != -1) {
      title = title.substring(0, extDot);
    }
    // Replace dots, underscores, dashes with space
    title = title.replaceAll(RegExp(r'[\._\-]'), ' ');

    // Strip common release tags
    title = title.replaceAll(
      RegExp(
        r'\b(1080p|720p|480p|2160p|4k|bluray|brrip|bdrip|dvdrip|web-dl|webrip|web|hdrip|x264|x265|hevc|aac|yify|yts|proper|repack|hdr|10bit|dual audio)\b',
        caseSensitive: false,
      ),
      '',
    );

    // Remove brackets content
    title = title.replaceAll(RegExp(r'\[.*?\]|\(.*?\)', caseSensitive: false), '');
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    return title;
  }

  Future<void> _performSearch() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _results = [];
    });

    try {
      final langParam = _selectedLang == 'all' ? '' : 'sublanguageid-$_selectedLang/';
      final url = 'https://rest.opensubtitles.org/search/${langParam}query-${Uri.encodeComponent(query)}';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'TemporaryUserAgent',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is List) {
          final items = decoded
              .whereType<Map<String, dynamic>>()
              .map((j) => SubtitleSearchResult.fromJson(j))
              .where((s) => s.downloadLink.isNotEmpty)
              .toList();

          setState(() {
            _results = items;
            _isSearching = false;
            if (items.isEmpty) {
              _errorMessage = 'No subtitles found for "$query". Try modifying your search keywords.';
            }
          });
          return;
        }
      }

      setState(() {
        _isSearching = false;
        _errorMessage = 'Subtitle service returned status ${response.statusCode}. Please try again.';
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _errorMessage = 'Could not fetch online subtitles ($e). Check your internet connection.';
      });
    }
  }

  Future<void> _downloadAndApply(SubtitleSearchResult sub) async {
    setState(() => _downloadingSubUrl = sub.downloadLink);

    try {
      final response = await http.get(
        Uri.parse(sub.downloadLink),
        headers: {'User-Agent': 'TemporaryUserAgent'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        List<int> srtBytes;

        // Check if response is gzip compressed
        if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
          srtBytes = gzip.decode(bytes);
        } else {
          srtBytes = bytes;
        }

        final tempDir = await getTemporaryDirectory();
        final subDir = Directory('${tempDir.path}/subtitles');
        if (!subDir.existsSync()) {
          subDir.createSync(recursive: true);
        }

        final cleanName = sub.subFileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final targetPath = '${subDir.path}/$cleanName';
        final subFile = File(targetPath);
        await subFile.writeAsBytes(srtBytes);

        await widget.playerWrapper.loadExternalSubtitle(targetPath);

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppTheme.accentCyan, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Subtitle Loaded: ${sub.subFileName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF131927),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.accentCyan, width: 0.8),
              ),
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download subtitle (HTTP ${response.statusCode})'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading subtitle: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingSubUrl = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C101A).withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom > 0
            ? MediaQuery.of(context).padding.bottom + 12 + bottomInset
            : 20 + bottomInset,
      ),
      constraints: BoxConstraints(maxHeight: screenH * 0.88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag pill
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: AppTheme.auraGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_download_rounded, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Search Online Subtitles',
                      style: AppTheme.headline.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Download directly from OpenSubtitles database',
                      style: AppTheme.caption.copyWith(color: AppTheme.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 22, color: AppTheme.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Search Box with Action
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF161C2C),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: TextField(
                    controller: _queryController,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    onSubmitted: (_) => _performSearch(),
                    decoration: InputDecoration(
                      hintText: 'Movie or Show title...',
                      hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.textSecondary),
                      suffixIcon: _queryController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16, color: AppTheme.textSecondary),
                              onPressed: () {
                                _queryController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _isSearching ? null : _performSearch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentCyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _isSearching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text(
                        'Search',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Horizontal Language Chips
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _languages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final item = _languages[index];
                final isSelected = item['code'] == _selectedLang;
                return ChoiceChip(
                  label: Text(
                    item['label']!,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? Colors.white : Colors.white70,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: AppTheme.accent.withValues(alpha: 0.65),
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  side: BorderSide(
                    color: isSelected ? AppTheme.accent : Colors.white12,
                    width: isSelected ? 1.2 : 0.6,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedLang = item['code']!);
                      _performSearch();
                    }
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Divider
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 8),

          // Content Area: Results, Loading, or Empty Error
          Expanded(
            child: _isSearching
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: AppTheme.accentCyan),
                        const SizedBox(height: 14),
                        Text(
                          'Searching online subtitle database...',
                          style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  )
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.subtitles_off_rounded, size: 40, color: Colors.white38),
                              const SizedBox(height: 12),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed: _performSearch,
                                icon: const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text('Try Again'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.accentCyan,
                                  side: const BorderSide(color: AppTheme.accentCyan),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _results.isEmpty
                        ? Center(
                            child: Text(
                              'Type video title above and press Search',
                              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _results.length,
                            separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                            itemBuilder: (context, index) {
                              final sub = _results[index];
                              final isDownloading = _downloadingSubUrl == sub.downloadLink;

                              return InkWell(
                                onTap: isDownloading ? null : () => _downloadAndApply(sub),
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppTheme.accent.withValues(alpha: 0.18),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
                                        ),
                                        child: Text(
                                          sub.langCode.toUpperCase(),
                                          style: const TextStyle(
                                            color: AppTheme.accentCyan,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              sub.subFileName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Row(
                                              children: [
                                                Text(
                                                  sub.languageName,
                                                  style: AppTheme.caption.copyWith(
                                                    color: AppTheme.textSecondary,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                const Icon(Icons.download_rounded, size: 12, color: Colors.white38),
                                                const SizedBox(width: 3),
                                                Text(
                                                  '${sub.downloadCount}',
                                                  style: AppTheme.caption.copyWith(fontSize: 11, color: Colors.white54),
                                                ),
                                                if (sub.rating > 0) ...[
                                                  const SizedBox(width: 10),
                                                  const Icon(Icons.star_rounded, size: 12, color: Colors.amber),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    sub.rating.toStringAsFixed(1),
                                                    style: AppTheme.caption.copyWith(fontSize: 11, color: Colors.amber),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (isDownloading)
                                        const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppTheme.accentCyan,
                                          ),
                                        )
                                      else
                                        IconButton(
                                          icon: const Icon(
                                            Icons.download_for_offline_rounded,
                                            color: AppTheme.accentCyan,
                                            size: 22,
                                          ),
                                          onPressed: () => _downloadAndApply(sub),
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
