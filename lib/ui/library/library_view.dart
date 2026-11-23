import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../player/player_models.dart';
import '../../services/mobile_storage_service.dart';
import '../../services/thumbnail_service.dart';
import '../../settings/storage_service.dart';
import '../../state/player_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/frosted_glass.dart';
import '../modals/manage_folders_modal.dart';

enum LibraryViewMode {
  cinemaGrid,
  compactGrid,
  detailedList,
  folders,
}

class LibraryView extends ConsumerStatefulWidget {
  const LibraryView({super.key});

  @override
  ConsumerState<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends ConsumerState<LibraryView> with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedFolder;
  String? _selectedFolderGroup;
  List<VideoFileItem> _scannedFiles = [];
  bool _isLoading = false;
  bool _hasStoragePermission = true;

  final List<String> _videoExtensions = [
    '.mp4', '.mkv', '.avi', '.webm', '.mov', '.flv', '.wmv', '.ts', '.m4v'
  ];

  String _sortMode = 'recent'; // 'recent', 'name_asc', 'name_desc', 'size_desc'
  LibraryViewMode _viewMode = LibraryViewMode.cinemaGrid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ThumbnailService.updateNotifier.addListener(_onThumbnailsUpdated);
    _checkPermissionAndScan();
  }

  void _onThumbnailsUpdated() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ThumbnailService.updateNotifier.removeListener(_onThumbnailsUpdated);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissionAndScan();
    }
  }

  Future<void> _checkPermissionAndScan() async {
    final granted = await MobileStorageService.hasStoragePermission();
    if (mounted) {
      setState(() => _hasStoragePermission = granted);
    }
    await _scanAllImportedFolders();
  }

  Future<void> _scanAllImportedFolders() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final storage = ref.read(storageServiceProvider);
    final folders = storage.getImportedFolders();

    final List<VideoFileItem> files = [];
    final seenPaths = <String>{};

    void addSafe(VideoFileItem item) {
      if (seenPaths.add(item.path)) {
        files.add(item);
      }
    }

    // 1. Android Native MediaStore Instant Query (VLC mode - 20ms)
    if (Platform.isAndroid && _hasStoragePermission) {
      final mediaVideos = await MobileStorageService.queryMediaVideos();
      for (final v in mediaVideos) {
        addSafe(v);
      }
    }

    // 2. Explicitly imported custom folders by user (scanned asynchronously in background isolate)
    for (final folderPath in folders) {
      final customVideos = await MobileStorageService.scanDirectoryAsync(
        folderPath,
        videoExtensions: _videoExtensions,
      );
      for (final v in customVideos) {
        addSafe(v);
      }
    }

    if (mounted) {
      setState(() {
        _scannedFiles = files;
        _isLoading = false;
      });
    }
  }

  Future<void> _importFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null) {
      await ref.read(storageServiceProvider).addImportedFolder(path);
      await _scanAllImportedFolders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added folder to library: ${path.split(RegExp(r'[/\\]')).last}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _importFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mkv', 'avi', 'webm', 'mov', 'flv', 'wmv', 'ts', 'm4v'],
      allowMultiple: true,
    );

    if (result != null && result.paths.isNotEmpty) {
      final storage = ref.read(storageServiceProvider);
      final validPaths = result.paths.whereType<String>().toList();
      for (final p in validPaths) {
        final parentDir = File(p).parent.path;
        await storage.addImportedFolder(parentDir);
      }
      await _scanAllImportedFolders();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${validPaths.length} video(s) to library'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _playAll({bool shuffle = false}) {
    var files = [..._filteredFiles];
    if (shuffle) files.shuffle();
    if (files.isNotEmpty) {
      final items = files.map((f) => PlaylistItem(
            path: f.path,
            title: f.title,
          )).toList();
      ref.read(playlistProvider.notifier).setList(items, initialIndex: 0);
    }
  }

  List<VideoFileItem> get _filteredFiles {
    var list = [..._scannedFiles];
    if (_selectedFolder != null) {
      list = list.where((f) => f.path.startsWith(_selectedFolder!)).toList();
    }
    if (_selectedFolderGroup != null) {
      list = list.where((f) => f.folderName == _selectedFolderGroup).toList();
    }
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((f) => f.name.toLowerCase().contains(q) || f.path.toLowerCase().contains(q)).toList();
    }

    switch (_sortMode) {
      case 'name_asc':
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case 'name_desc':
        list.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case 'size_desc':
        list.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
        break;
      case 'recent':
      default:
        list.sort((a, b) => b.dateModifiedMs.compareTo(a.dateModifiedMs));
        break;
    }

    return list;
  }

  Map<String, List<VideoFileItem>> get _folderGroups {
    final map = <String, List<VideoFileItem>>{};
    for (final f in _scannedFiles) {
      map.putIfAbsent(f.folderName, () => []).add(f);
    }
    return map;
  }

  VideoFileItem? _getHeroFeaturedFile(List<VideoFileItem> files) {
    if (files.isEmpty) return null;
    final storage = ref.read(storageServiceProvider);
    final recents = storage.getRecentFiles();
    for (final recent in recents) {
      for (final f in files) {
        if (f.path == recent.path) {
          return f;
        }
      }
    }
    return files.first;
  }

  String _formatFileSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  int _calculateTotalSize(List<VideoFileItem> files) {
    int total = 0;
    for (final f in files) {
      total += f.sizeBytes;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(storageServiceProvider);
    final importedFolders = storage.getImportedFolders();
    final filtered = _filteredFiles;
    final totalBytes = _calculateTotalSize(filtered);
    final heroFeatured = _getHeroFeaturedFile(filtered);
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final textPrimary = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final borderCol = isDark ? AppTheme.glassBorder : AppTheme.lightGlassBorder;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Column(
          children: [
            // Single Unified Cinema Search & Filter Strip with Frosted Glass Blur
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: MediaQuery.of(context).size.width < 600 ? 14 : 28,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.surface.withValues(alpha: 0.22)
                        : Colors.white.withValues(alpha: 0.38),
                    border: Border(
                      bottom: BorderSide(color: borderCol, width: 0.5),
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 650;
                      if (isMobile) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: isDark ? AppTheme.surfaceSecondary : Colors.white.withValues(alpha: 0.85),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: borderCol),
                                    ),
                                    child: TextField(
                                      controller: _searchController,
                                      style: TextStyle(color: textPrimary, fontSize: 13),
                                      onChanged: (_) => setState(() {}),
                                      decoration: InputDecoration(
                                        hintText: 'Search ${_scannedFiles.length} videos...',
                                        hintStyle: TextStyle(color: textSecondary, fontSize: 13),
                                        prefixIcon: Icon(Icons.search_rounded, size: 16, color: textSecondary),
                                        suffixIcon: _searchController.text.isNotEmpty
                                            ? IconButton(
                                                icon: Icon(Icons.close_rounded, size: 15, color: textSecondary),
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
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Add Video Files',
                                  icon: const Icon(Icons.video_file_rounded, color: AppTheme.accentCyan),
                                  onPressed: _importFiles,
                                ),
                                IconButton(
                                  tooltip: 'Add Folder',
                                  icon: Icon(Icons.create_new_folder_rounded, color: textPrimary),
                                  onPressed: _importFolder,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 34,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  _folderChip(
                                    label: 'All Media (${_scannedFiles.length})',
                                    isSelected: _selectedFolder == null,
                                    onTap: () => setState(() => _selectedFolder = null),
                                  ),
                                  ...importedFolders.map((folder) {
                                    final name = folder.split(RegExp(r'[/\\]')).last;
                                    final count = _scannedFiles.where((f) => f.path.startsWith(folder)).length;
                                    return _folderChip(
                                      label: '$name ($count)',
                                      isSelected: _selectedFolder == folder,
                                      onTap: () => setState(() => _selectedFolder = folder),
                                      onDelete: () async {
                                        await storage.removeImportedFolder(folder);
                                        if (_selectedFolder == folder) _selectedFolder = null;
                                        await _scanAllImportedFolders();
                                      },
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          // 1. Search Field
                          Container(
                            width: 250,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.surfaceSecondary : Colors.white.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: borderCol),
                            ),
                            child: TextField(
                              controller: _searchController,
                              style: TextStyle(color: textPrimary, fontSize: 13),
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: 'Search ${_scannedFiles.length} videos...',
                                hintStyle: TextStyle(color: textSecondary, fontSize: 13),
                                prefixIcon: Icon(Icons.search_rounded, size: 16, color: textSecondary),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(Icons.close_rounded, size: 15, color: textSecondary),
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

                          const SizedBox(width: 14),

                          // 2. Folder Filter Chips (Horizontal List)
                          Expanded(
                            child: SizedBox(
                              height: 38,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  _folderChip(
                                    label: 'All Media (${_scannedFiles.length})',
                                    isSelected: _selectedFolder == null,
                                    onTap: () => setState(() => _selectedFolder = null),
                                  ),
                                  ...importedFolders.map((folder) {
                                    final name = folder.split(RegExp(r'[/\\]')).last;
                                    final count = _scannedFiles.where((f) => f.path.startsWith(folder)).length;
                                    return _folderChip(
                                      label: '$name ($count)',
                                      isSelected: _selectedFolder == folder,
                                      onTap: () => setState(() => _selectedFolder = folder),
                                      onDelete: () async {
                                        await storage.removeImportedFolder(folder);
                                        if (_selectedFolder == folder) _selectedFolder = null;
                                        await _scanAllImportedFolders();
                                      },
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(width: 14),

                          // 3. Quick Actions: Add Folder, Manage Folders, Remove Folder & Add Files
                          if (_selectedFolder != null) ...[
                            OutlinedButton.icon(
                              onPressed: () async {
                                final folderToRemove = _selectedFolder!;
                                await storage.removeImportedFolder(folderToRemove);
                                setState(() => _selectedFolder = null);
                                await _scanAllImportedFolders();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Removed folder from library: ${folderToRemove.split(RegExp(r'[/\\]')).last}'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.delete_outline_rounded, size: 15, color: Color(0xFFF43F5E)),
                              label: const Text('Remove Folder', style: TextStyle(color: Color(0xFFF43F5E))),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFF43F5E),
                                side: BorderSide(color: const Color(0xFFF43F5E).withValues(alpha: 0.5)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                textStyle: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          OutlinedButton.icon(
                            onPressed: () => ManageFoldersModal.show(context, onFoldersChanged: _scanAllImportedFolders),
                            icon: Icon(Icons.folder_shared_rounded, size: 15, color: textPrimary),
                            label: Text('Manage Folders', style: TextStyle(color: textPrimary)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: textPrimary,
                              side: BorderSide(color: borderCol),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              textStyle: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _importFolder,
                            icon: Icon(Icons.create_new_folder_rounded, size: 15, color: textPrimary),
                            label: Text('Add Folder', style: TextStyle(color: textPrimary)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: textPrimary,
                              side: BorderSide(color: borderCol),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              textStyle: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _importFiles,
                            icon: Icon(Icons.add_rounded, size: 16, color: textPrimary),
                            label: Text('Add Files', style: TextStyle(color: textPrimary)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: textPrimary,
                              side: BorderSide(color: borderCol),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              textStyle: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),

            // Main Content Area
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
                  : (filtered.isEmpty && !Platform.isAndroid) || (filtered.isEmpty && _hasStoragePermission)
                      ? _emptyLibraryView()
                      : CustomScrollView(
                          slivers: [
                            // 0. VLC-style All Files Access Banner on Android
                            if (Platform.isAndroid && !_hasStoragePermission)
                              SliverToBoxAdapter(
                                child: _buildPermissionBanner(isDark, borderCol, textPrimary, textSecondary),
                              ),

                            if (filtered.isEmpty)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: _emptyLibraryView(),
                              )
                            else ...[
                              // 1. Apple TV / Infuse 8 Cinematic Hero Spotlight
                              if (_searchController.text.isEmpty && heroFeatured != null && _viewMode != LibraryViewMode.folders)
                                SliverToBoxAdapter(
                                  child: _buildHeroSpotlight(heroFeatured),
                                ),

                              // 2. Continue Watching Carousel
                              if (_searchController.text.isEmpty && _viewMode != LibraryViewMode.folders)
                                _buildContinueWatchingSliver(storage, isDark, textPrimary, textSecondary, borderCol),

                              // Folder breadcrumb if drilled down into a folder
                              if (_viewMode == LibraryViewMode.folders && _selectedFolderGroup != null)
                                SliverToBoxAdapter(
                                  child: _buildFolderBreadcrumb(_selectedFolderGroup!, filtered.length, textPrimary, textSecondary, borderCol, isDark),
                                ),

                              // 2. Stats & Quick Actions Toolbar
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: MediaQuery.of(context).size.width < 600 ? 12 : 28,
                                    vertical: 8,
                                  ),
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final isSmall = constraints.maxWidth < 650;
                                      final titleText = _viewMode == LibraryViewMode.folders && _selectedFolderGroup == null
                                          ? '${_folderGroups.length} FOLDERS'
                                          : '${filtered.length} TITLES';

                                      final countWidget = Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            titleText,
                                            style: AppTheme.caption.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: textPrimary,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '• ${_formatFileSize(totalBytes)}',
                                            style: AppTheme.caption.copyWith(
                                              color: textSecondary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      );

                                      final controlsWidget = Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Sort Dropdown Menu
                                          PopupMenuButton<String>(
                                            tooltip: 'Sort By',
                                            color: isDark ? AppTheme.surface.withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              side: BorderSide(color: borderCol),
                                            ),
                                            onSelected: (val) => setState(() => _sortMode = val),
                                            itemBuilder: (ctx) => [
                                              PopupMenuItem(
                                                value: 'recent',
                                                height: 32,
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.access_time_rounded, size: 15, color: _sortMode == 'recent' ? AppTheme.accent : textSecondary),
                                                    const SizedBox(width: 8),
                                                    Text('Recently Added', style: TextStyle(fontSize: 12.5, color: _sortMode == 'recent' ? AppTheme.accent : textPrimary)),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'name_asc',
                                                height: 32,
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.sort_by_alpha_rounded, size: 15, color: _sortMode == 'name_asc' ? AppTheme.accent : textSecondary),
                                                    const SizedBox(width: 8),
                                                    Text('Name (A to Z)', style: TextStyle(fontSize: 12.5, color: _sortMode == 'name_asc' ? AppTheme.accent : textPrimary)),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'name_desc',
                                                height: 32,
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.sort_by_alpha_rounded, size: 15, color: _sortMode == 'name_desc' ? AppTheme.accent : textSecondary),
                                                    const SizedBox(width: 8),
                                                    Text('Name (Z to A)', style: TextStyle(fontSize: 12.5, color: _sortMode == 'name_desc' ? AppTheme.accent : textPrimary)),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'size_desc',
                                                height: 32,
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.data_usage_rounded, size: 15, color: _sortMode == 'size_desc' ? AppTheme.accent : textSecondary),
                                                    const SizedBox(width: 8),
                                                    Text('File Size (Largest)', style: TextStyle(fontSize: 12.5, color: _sortMode == 'size_desc' ? AppTheme.accent : textPrimary)),
                                                  ],
                                                ),
                                              ),
                                            ],
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: isDark ? AppTheme.surfaceSecondary : Colors.white.withValues(alpha: 0.85),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: borderCol),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.swap_vert_rounded, size: 14, color: AppTheme.accent),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    _sortMode == 'recent'
                                                        ? 'Recent'
                                                        : _sortMode == 'name_asc'
                                                            ? 'A-Z'
                                                            : _sortMode == 'name_desc'
                                                                ? 'Z-A'
                                                                : 'Size',
                                                    style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600, color: textPrimary, fontSize: 11.5),
                                                  ),
                                                  Icon(Icons.keyboard_arrow_down_rounded, size: 13, color: textSecondary),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),

                                          // 4-Way View Mode Toggle
                                          Container(
                                            decoration: BoxDecoration(
                                              color: isDark ? AppTheme.surfaceSecondary : Colors.white.withValues(alpha: 0.85),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: borderCol),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                _viewModeButton(
                                                  mode: LibraryViewMode.cinemaGrid,
                                                  icon: Icons.grid_view_rounded,
                                                  tooltip: 'Cinema Cards',
                                                  isFirst: true,
                                                ),
                                                Container(width: 1, height: 16, color: borderCol),
                                                _viewModeButton(
                                                  mode: LibraryViewMode.compactGrid,
                                                  icon: Icons.view_comfy_rounded,
                                                  tooltip: 'Compact VLC Grid',
                                                ),
                                                Container(width: 1, height: 16, color: borderCol),
                                                _viewModeButton(
                                                  mode: LibraryViewMode.detailedList,
                                                  icon: Icons.view_list_rounded,
                                                  tooltip: 'Detailed List',
                                                ),
                                                Container(width: 1, height: 16, color: borderCol),
                                                _viewModeButton(
                                                  mode: LibraryViewMode.folders,
                                                  icon: Icons.folder_copy_rounded,
                                                  tooltip: 'Folder View',
                                                  isLast: true,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 6),

                                          IconButton(
                                            tooltip: 'Play All',
                                            icon: const Icon(Icons.play_circle_fill_rounded, color: AppTheme.accent, size: 24),
                                            padding: const EdgeInsets.all(4),
                                            constraints: const BoxConstraints(),
                                            onPressed: () => _playAll(shuffle: false),
                                          ),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            tooltip: 'Shuffle',
                                            icon: Icon(Icons.shuffle_rounded, color: textSecondary, size: 20),
                                            padding: const EdgeInsets.all(4),
                                            constraints: const BoxConstraints(),
                                            onPressed: () => _playAll(shuffle: true),
                                          ),
                                        ],
                                      );

                                      if (isSmall) {
                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                countWidget,
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              physics: const BouncingScrollPhysics(),
                                              child: controlsWidget,
                                            ),
                                          ],
                                        );
                                      }

                                      return Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          countWidget,
                                          controlsWidget,
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),

                              // 3. Media Presentation (Cinema Grid, Compact Grid, List, or Folders)
                              if (_viewMode == LibraryViewMode.folders && _selectedFolderGroup == null)
                                SliverPadding(
                                  padding: EdgeInsets.fromLTRB(
                                    MediaQuery.of(context).size.width < 600 ? 12 : 28,
                                    4,
                                    MediaQuery.of(context).size.width < 600 ? 12 : 28,
                                    32,
                                  ),
                                  sliver: SliverGrid(
                                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 220,
                                      mainAxisExtent: 165,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final groups = _folderGroups;
                                        final folderName = groups.keys.elementAt(index);
                                        return _folderCard(folderName, groups[folderName]!);
                                      },
                                      childCount: _folderGroups.length,
                                    ),
                                  ),
                                )
                              else if (_viewMode == LibraryViewMode.compactGrid || (_viewMode == LibraryViewMode.folders && _selectedFolderGroup != null))
                                SliverPadding(
                                  padding: EdgeInsets.fromLTRB(
                                    MediaQuery.of(context).size.width < 600 ? 10 : 28,
                                    4,
                                    MediaQuery.of(context).size.width < 600 ? 10 : 28,
                                    32,
                                  ),
                                  sliver: SliverGrid(
                                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 135,
                                      mainAxisExtent: 175,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) => _compactVideoCard(filtered[index]),
                                      childCount: filtered.length,
                                    ),
                                  ),
                                )
                              else if (_viewMode == LibraryViewMode.cinemaGrid)
                                SliverPadding(
                                  padding: EdgeInsets.fromLTRB(
                                    MediaQuery.of(context).size.width < 600 ? 12 : 28,
                                    4,
                                    MediaQuery.of(context).size.width < 600 ? 12 : 28,
                                    32,
                                  ),
                                  sliver: SliverGrid(
                                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: MediaQuery.of(context).size.width < 600 ? 240 : 310,
                                      mainAxisExtent: 235,
                                      crossAxisSpacing: 14,
                                      mainAxisSpacing: 14,
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final file = filtered[index];
                                        return _videoCard(file);
                                      },
                                      childCount: filtered.length,
                                    ),
                                  ),
                                )
                              else
                                SliverPadding(
                                  padding: EdgeInsets.fromLTRB(
                                    MediaQuery.of(context).size.width < 600 ? 12 : 28,
                                    4,
                                    MediaQuery.of(context).size.width < 600 ? 12 : 28,
                                    32,
                                  ),
                                  sliver: SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final file = filtered[index];
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: _videoListTile(file),
                                        );
                                      },
                                      childCount: filtered.length,
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
            ),
          ],
        ),
      );
  }

  Widget _buildPermissionBanner(bool isDark, Color borderCol, Color textPrimary, Color textSecondary) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E1B4B).withValues(alpha: 0.85), const Color(0xFF3B0764).withValues(alpha: 0.85)]
              : [const Color(0xFFEDE9FE), const Color(0xFFFCE7F3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.5), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accent.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.accent, width: 1.5),
            ),
            child: const Center(
              child: Icon(Icons.folder_special_rounded, color: AppTheme.accent, size: 24),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'VLC-Style Storage Access',
                  style: AppTheme.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Allow "All files access" to automatically browse all videos on your phone without privacy blocks.',
                  style: AppTheme.caption.copyWith(
                    color: textSecondary,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () async {
              await MobileStorageService.requestStoragePermission();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: const Color(0xFF04131F),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Allow', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderBreadcrumb(String folderName, int count, Color textPrimary, Color textSecondary, Color borderCol, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceSecondary : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => setState(() => _selectedFolderGroup = null),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_back_rounded, size: 16, color: AppTheme.accent),
                  const SizedBox(width: 6),
                  Text(
                    'All Folders',
                    style: TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, size: 16, color: textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$folderName ($count)',
              style: TextStyle(
                color: textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewModeButton({
    required LibraryViewMode mode,
    required IconData icon,
    required String tooltip,
    bool isFirst = false,
    bool isLast = false,
  }) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final isSelected = _viewMode == mode;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          setState(() {
            _viewMode = mode;
            if (mode != LibraryViewMode.folders) {
              _selectedFolderGroup = null;
            }
          });
        },
        borderRadius: BorderRadius.horizontal(
          left: isFirst ? const Radius.circular(8) : Radius.zero,
          right: isLast ? const Radius.circular(8) : Radius.zero,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.accent.withValues(alpha: 0.25) : Colors.transparent,
            borderRadius: BorderRadius.horizontal(
              left: isFirst ? const Radius.circular(8) : Radius.zero,
              right: isLast ? const Radius.circular(8) : Radius.zero,
            ),
          ),
          child: Icon(
            icon,
            size: 15,
            color: isSelected ? AppTheme.accent : textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _compactVideoCard(VideoFileItem file) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final textPrimary = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final borderCol = isDark ? AppTheme.glassBorder : AppTheme.lightGlassBorder;
    final cardBg = isDark
        ? const Color(0xFF141926).withValues(alpha: 0.82)
        : Colors.white.withValues(alpha: 0.90);

    final storage = ref.read(storageServiceProvider);
    final savedPos = storage.getPosition(file.path);
    final thumb = ThumbnailService.getCachedThumbnail(file.path);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol, width: 0.8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            ref.read(playlistProvider.notifier).addItem(
                  PlaylistItem(path: file.path, title: file.title),
                  playImmediately: true,
                );
          },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thumbnail Area
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (thumb != null)
                    Image.file(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _fallbackThumb(),
                    )
                  else
                    _fallbackThumb(),

                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.65),
                        ],
                        stops: const [0.5, 1.0],
                      ),
                    ),
                  ),

                  // Format Badge
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        file.extension,
                        style: AppTheme.caption.copyWith(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
                  ),

                  // Duration Badge (Bottom-Right, VLC Style)
                  if (file.formattedDuration.isNotEmpty)
                    Positioned(
                      bottom: 5,
                      right: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          file.formattedDuration,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),

                  // Play Button (center subtle)
                  Center(
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.5),
                      ),
                      child: const Center(
                        child: Icon(Icons.play_arrow_rounded, size: 20, color: Colors.white),
                      ),
                    ),
                  ),

                  // Resume progress bar if partially watched
                  if (savedPos.inSeconds > 5)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 3,
                        color: Colors.white24,
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 0.45,
                          child: Container(color: AppTheme.accent),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Title & size info
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  file.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                    height: 1.25,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      file.formattedSize,
                      style: TextStyle(
                        fontSize: 10,
                        color: textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (savedPos.inSeconds > 5)
                      Text(
                        _formatDuration(savedPos),
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
          ),
        ),
    );
  }

  Widget _folderCard(String folderName, List<VideoFileItem> files) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final textPrimary = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final borderCol = isDark ? AppTheme.glassBorder : AppTheme.lightGlassBorder;
    final cardBg = isDark
        ? const Color(0xFF141926).withValues(alpha: 0.82)
        : Colors.white.withValues(alpha: 0.90);

    final totalBytes = _calculateTotalSize(files);
    final firstThumb = files.isNotEmpty
        ? ThumbnailService.getCachedThumbnail(files.first.path)
        : null;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderCol, width: 0.8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() {
              _selectedFolderGroup = folderName;
            });
          },
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Preview (first video thumbnail or graphic)
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (firstThumb != null)
                    Image.file(firstThumb, fit: BoxFit.cover, errorBuilder: (_, _, _) => _folderGraphic())
                  else
                    _folderGraphic(),

                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.6),
                        ],
                      ),
                    ),
                  ),

                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.folder_rounded, size: 14, color: AppTheme.accent),
                          const SizedBox(width: 5),
                          Text(
                            '${files.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Folder Name & Details
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  folderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${files.length} video${files.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 11,
                        color: textSecondary,
                      ),
                    ),
                    Text(
                      _formatFileSize(totalBytes),
                      style: TextStyle(
                        fontSize: 11,
                        color: textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
          ),
        ),
    );
  }

  Widget _folderGraphic() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(Icons.folder_rounded, size: 28, color: AppTheme.accent),
          ),
        ),
      ),
    );
  }

  Widget _buildContinueWatchingSliver(
    StorageService storage,
    bool isDark,
    Color textPrimary,
    Color textSecondary,
    Color borderCol,
  ) {
    final recentList = storage.getRecentFiles();
    final inProgress = recentList.where((item) {
      final posSec = item.position.inSeconds;
      final durSec = item.duration.inSeconds;
      if (posSec < 5) return false;
      if (durSec > 0 && posSec >= durSec - 10) return false;
      return true;
    }).toList();

    if (inProgress.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              MediaQuery.of(context).size.width < 600 ? 14 : 28,
              12,
              14,
              8,
            ),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    gradient: AppTheme.auraGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded, size: 15, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Text(
                  'CONTINUE WATCHING',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4), width: 0.8),
                  ),
                  child: Text(
                    '${inProgress.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accentCyan,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 165,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width < 600 ? 14 : 28,
                vertical: 4,
              ),
              scrollDirection: Axis.horizontal,
              itemCount: inProgress.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final item = inProgress[index];
                final thumb = ThumbnailService.getCachedThumbnail(item.path);
                final totalMs = item.duration.inMilliseconds;
                final posMs = item.position.inMilliseconds;
                final frac = totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0;
                final remaining = item.duration - item.position;
                final remStr = remaining.inHours > 0
                    ? '${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m left'
                    : (remaining.inMinutes > 0 ? '${remaining.inMinutes}m left' : '${remaining.inSeconds}s left');

                return InkWell(
                  onTap: () {
                    ref.read(playlistProvider.notifier).setList([
                      PlaylistItem(path: item.path, title: item.title),
                    ], initialIndex: 0);
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 200,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF131826) : Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderCol, width: 0.8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Thumbnail Container
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                              child: SizedBox(
                                width: 200,
                                height: 108,
                                child: thumb != null && thumb.existsSync()
                                    ? Image.file(thumb, fit: BoxFit.cover)
                                    : Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: isDark
                                                ? [const Color(0xFF1E2438), const Color(0xFF0F1320)]
                                                : [Colors.grey.shade300, Colors.grey.shade100],
                                          ),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            Icons.movie_filter_rounded,
                                            size: 30,
                                            color: textSecondary.withValues(alpha: 0.4),
                                          ),
                                        ),
                                      ),
                              ),
                            ),

                            // Center Play Icon Badge
                            Positioned.fill(
                              child: Center(
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white24, width: 1.2),
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),

                            // Close / Dismiss button
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () async {
                                    await storage.removeRecentFile(item.path);
                                    if (mounted) setState(() {});
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.60),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      size: 13,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Remaining time badge (bottom-right of thumbnail)
                            if (item.duration > Duration.zero)
                              Positioned(
                                bottom: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.78),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.white12, width: 0.6),
                                  ),
                                  child: Text(
                                    remStr,
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),

                            // Gradient Progress Bar (pinned at bottom of thumbnail)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: SizedBox(
                                height: 3.5,
                                child: LinearProgressIndicator(
                                  value: frac,
                                  backgroundColor: Colors.white24,
                                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentCyan),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Title & Subtitle Info
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.path.split(RegExp(r'[/\\]')).firstWhere((_) => true, orElse: () => ''),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildHeroSpotlight(VideoFileItem file) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final textPrimary = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final borderCol = isDark ? AppTheme.glassBorder : AppTheme.lightGlassBorder;

    final cleanTitle = file.title;
    final ext = file.extension;
    final storage = ref.read(storageServiceProvider);
    final savedPos = storage.getPosition(file.path);
    final thumb = ThumbnailService.getCachedThumbnail(file.path);
    final sizeBytes = file.sizeBytes;

    final scrimColor = isDark ? const Color(0xFF0D0D12) : const Color(0xFFF1F5F9);

    return Container(
      margin: EdgeInsets.fromLTRB(
        MediaQuery.of(context).size.width < 600 ? 12 : 28,
        12,
        MediaQuery.of(context).size.width < 600 ? 12 : 28,
        6,
      ),
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderCol, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background image (thumbnail cover with gradient scrim)
            if (thumb != null)
              Positioned.fill(
                child: Image.file(
                  thumb,
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                  errorBuilder: (_, _, _) => _fallbackThumb(),
                ),
              )
            else
              Positioned.fill(child: _fallbackThumb()),

            // Cinematic multi-directional gradient scrim
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      scrimColor,
                      scrimColor.withValues(alpha: 0.95),
                      scrimColor.withValues(alpha: 0.75),
                      scrimColor.withValues(alpha: 0.25),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.40, 0.65, 0.85, 1.0],
                  ),
                ),
              ),
            ),

            // Content Left Overlay
            Positioned(
              top: MediaQuery.of(context).size.width < 600 ? 14 : 22,
              bottom: MediaQuery.of(context).size.width < 600 ? 14 : 22,
              left: MediaQuery.of(context).size.width < 600 ? 16 : 28,
              right: MediaQuery.of(context).size.width < 600 ? 16 : 180,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Badge Row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE11D48), Color(0xFFFA2D48)],
                          ),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accent.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome_rounded, size: 11, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              savedPos.inSeconds > 5 ? 'CONTINUE WATCHING' : 'FEATURED MEDIA',
                              style: AppTheme.caption.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 9.5,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: borderCol, width: 0.8),
                        ),
                        child: Text(
                          ext,
                          style: AppTheme.caption.copyWith(
                            color: textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      if (sizeBytes > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          _formatFileSize(sizeBytes),
                          style: AppTheme.caption.copyWith(
                            color: textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Hero Title
                  Text(
                    cleanTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.headline.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Subtitle / Status
                  Text(
                    savedPos.inSeconds > 5
                        ? 'Paused at ${_formatDuration(savedPos)} • Click resume to continue playback where you left off'
                        : 'Ready to play in ultra-smooth high definition with full hardware acceleration',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(
                      color: textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),

                  // Action Buttons
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          ref.read(playlistProvider.notifier).addItem(
                                PlaylistItem(path: file.path, title: cleanTitle),
                                playImmediately: true,
                              );
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 16),
                        label: Text(savedPos.inSeconds > 5 ? 'Resume Watching' : 'Play Now'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: const Color(0xFF04131F),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                          shadowColor: AppTheme.accent.withValues(alpha: 0.5),
                          textStyle: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (savedPos.inSeconds > 5) ...[
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: () {
                            storage.setPosition(file.path, Duration.zero);
                            ref.read(playlistProvider.notifier).addItem(
                                  PlaylistItem(path: file.path, title: cleanTitle),
                                  playImmediately: true,
                                );
                          },
                          icon: Icon(Icons.replay_rounded, size: 15, color: textPrimary),
                          label: Text('From Beginning', style: TextStyle(color: textPrimary)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: textPrimary,
                            side: BorderSide(color: borderCol),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            textStyle: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _folderChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    VoidCallback? onDelete,
  }) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final borderCol = isDark ? AppTheme.glassBorder : AppTheme.lightGlassBorder;

    return Container(
      margin: const EdgeInsets.only(right: 8),
      alignment: Alignment.center,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            gradient: isSelected ? AppTheme.auraGradient : null,
            color: isSelected ? null : (isDark ? AppTheme.surfaceSecondary : Colors.white.withValues(alpha: 0.85)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? Colors.transparent : borderCol,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.accent.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTheme.caption.copyWith(
                  color: isSelected ? const Color(0xFF04131F) : textSecondary,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onDelete,
                  child: Icon(
                    Icons.cancel_rounded,
                    size: 14,
                    color: isSelected ? const Color(0xFF04131F).withValues(alpha: 0.7) : textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _videoCard(VideoFileItem file) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final textPrimary = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final borderCol = isDark ? AppTheme.glassBorder : AppTheme.lightGlassBorder;
    final cardBg = isDark
        ? const Color(0xFF141926).withValues(alpha: 0.82)
        : Colors.white.withValues(alpha: 0.90);

    final storage = ref.read(storageServiceProvider);
    final savedPos = storage.getPosition(file.path);
    final thumb = ThumbnailService.getCachedThumbnail(file.path);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderCol, width: 0.8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            ref.read(playlistProvider.notifier).addItem(
                  PlaylistItem(path: file.path, title: file.title),
                  playImmediately: true,
                );
          },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 16:9 Cinematic Thumbnail Box
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Actual Thumbnail or High-End Cinema Fallback
                  if (thumb != null) ...[
                    Image.file(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _fallbackThumb(),
                    ),
                    // Cinematic dark bottom gradient vignette
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.25),
                            Colors.black.withValues(alpha: 0.75),
                          ],
                          stops: const [0.4, 0.7, 1.0],
                        ),
                      ),
                    ),
                  ] else ...[
                    _fallbackThumb(),
                  ],

                  // Top Badges Row (Format + Quality + 3-Dots Menu)
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Format Badge (e.g. MKV, MP4)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: borderCol),
                              ),
                              child: Text(
                                file.extension,
                                style: AppTheme.caption.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.accent,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),

                            // Resolution Badge
                            if (file.height >= 2160 || file.title.toLowerCase().contains('4k') || file.title.toLowerCase().contains('2160p'))
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAB308).withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  '4K HDR',
                                  style: AppTheme.caption.copyWith(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black,
                                  ),
                                ),
                              )
                            else if (file.height >= 1080 || file.title.toLowerCase().contains('1080p') || file.title.toLowerCase().contains('fhd'))
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentCyan.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  '1080P',
                                  style: AppTheme.caption.copyWith(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                          ],
                        ),

                        // 3-Dots Quick Actions Menu
                        PopupMenuButton<String>(
                          tooltip: 'Options',
                          color: isDark ? AppTheme.surface.withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: borderCol),
                          ),
                          onSelected: (val) async {
                            if (val == 'play') {
                              ref.read(playlistProvider.notifier).addItem(
                                    PlaylistItem(path: file.path, title: file.title),
                                    playImmediately: true,
                                  );
                            } else if (val == 'restart') {
                              storage.setPosition(file.path, Duration.zero);
                              ref.read(playlistProvider.notifier).addItem(
                                    PlaylistItem(path: file.path, title: file.title),
                                    playImmediately: true,
                                  );
                            } else if (val == 'queue') {
                              ref.read(playlistProvider.notifier).addItem(
                                    PlaylistItem(path: file.path, title: file.title),
                                    playImmediately: false,
                                  );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Added to playlist: ${file.title}'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            } else if (val == 'copy') {
                              final sm = ScaffoldMessenger.of(context);
                              await Clipboard.setData(ClipboardData(text: file.path));
                              sm.showSnackBar(
                                const SnackBar(
                                  content: Text('File path copied to clipboard'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                          itemBuilder: (ctx) => [
                            PopupMenuItem(
                              value: 'play',
                              height: 32,
                              child: Row(
                                children: [
                                  const Icon(Icons.play_arrow_rounded, size: 16, color: AppTheme.accent),
                                  const SizedBox(width: 8),
                                  Text('Play Now', style: TextStyle(fontSize: 12.5, color: textPrimary)),
                                ],
                              ),
                            ),
                            if (savedPos.inSeconds > 5)
                              PopupMenuItem(
                                value: 'restart',
                                height: 32,
                                child: Row(
                                  children: [
                                    Icon(Icons.replay_rounded, size: 15, color: textSecondary),
                                    const SizedBox(width: 8),
                                    Text('Play from Start', style: TextStyle(fontSize: 12.5, color: textPrimary)),
                                  ],
                                ),
                              ),
                            PopupMenuItem(
                              value: 'queue',
                              height: 32,
                              child: Row(
                                children: [
                                  Icon(Icons.playlist_add_rounded, size: 16, color: textSecondary),
                                  const SizedBox(width: 8),
                                  Text('Add to Queue', style: TextStyle(fontSize: 12.5, color: textPrimary)),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(height: 1),
                            PopupMenuItem(
                              value: 'copy',
                              height: 32,
                              child: Row(
                                children: [
                                  Icon(Icons.content_copy_rounded, size: 15, color: textSecondary),
                                  const SizedBox(width: 8),
                                  Text('Copy Path', style: TextStyle(fontSize: 12.5, color: textPrimary)),
                                ],
                              ),
                            ),
                          ],
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.black.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Icon(Icons.more_vert, size: 20, color: textPrimary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Center Play Button Overlay
                  Center(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.55),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.play_arrow_rounded, size: 24, color: Colors.white),
                      ),
                    ),
                  ),

                  // Duration Badge (Bottom-Right, VLC Style)
                  if (file.formattedDuration.isNotEmpty)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          file.formattedDuration,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                  // Resume Watch Progress Line
                  if (savedPos.inSeconds > 5)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 3.5,
                        decoration: const BoxDecoration(
                          color: Colors.white24,
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 0.45,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: AppTheme.accent,
                              boxShadow: [
                                BoxShadow(color: AppTheme.accent, blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Metadata Details Strip
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    letterSpacing: 0.2,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      savedPos.inSeconds > 5
                          ? 'Resume at ${_formatDuration(savedPos)}'
                          : file.formattedSize,
                      style: AppTheme.caption.copyWith(
                        color: savedPos.inSeconds > 5 ? AppTheme.accent : textSecondary,
                        fontSize: 11,
                        fontWeight: savedPos.inSeconds > 5 ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    Text(
                      file.folderName,
                      style: AppTheme.caption.copyWith(
                        color: textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
          ),
        ),
    );
  }

  Widget _videoListTile(VideoFileItem file) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final textPrimary = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final borderCol = isDark ? AppTheme.glassBorder : AppTheme.lightGlassBorder;
    final cardBg = isDark
        ? const Color(0xFF141926).withValues(alpha: 0.85)
        : Colors.white.withValues(alpha: 0.92);

    final storage = ref.read(storageServiceProvider);
    final savedPos = storage.getPosition(file.path);

    final thumb = ThumbnailService.getCachedThumbnail(file.path);
    if (thumb == null) {
      ThumbnailService.generateThumbnail(file.path);
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol, width: 0.8),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            ref.read(playlistProvider.notifier).addItem(
                  PlaylistItem(path: file.path, title: file.title),
                  playImmediately: true,
                );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // 1. Mini 16:9 Thumbnail with duration overlay
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 80,
                    height: 50,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF141620) : const Color(0xFFE2E8F0),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (thumb != null)
                          Image.file(
                            thumb,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _fallbackThumb(),
                          )
                        else
                          _fallbackThumb(),

                        // Duration Badge on bottom-right of thumbnail
                        if (file.formattedDuration.isNotEmpty)
                          Positioned(
                            bottom: 3,
                            right: 3,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.78),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                file.formattedDuration,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // 2. Format Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: borderCol),
                  ),
                  child: Text(
                    file.extension,
                    style: AppTheme.caption.copyWith(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accent,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // 3. Title & Path Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: file.name,
                        child: Text(
                          file.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.folder_open_rounded, size: 12, color: textSecondary),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              file.folderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.caption.copyWith(color: textSecondary, fontSize: 11),
                            ),
                          ),
                          if (savedPos.inSeconds > 5) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.5), width: 0.5),
                              ),
                              child: Text(
                                'Resume ${_formatDuration(savedPos)}',
                                style: AppTheme.caption.copyWith(
                                  color: AppTheme.accent,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // 4. Pre-calculated Instant File Size
                Text(
                  file.formattedSize,
                  style: AppTheme.caption.copyWith(
                    color: textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                  ),
                ),

                const SizedBox(width: 6),

                // 5. 3-Dots Menu
                PopupMenuButton<String>(
                  tooltip: 'Options',
                  color: isDark ? AppTheme.surface.withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: borderCol),
                  ),
                  onSelected: (val) async {
                    if (val == 'play') {
                      ref.read(playlistProvider.notifier).addItem(
                            PlaylistItem(path: file.path, title: file.title),
                            playImmediately: true,
                          );
                    } else if (val == 'restart') {
                      storage.setPosition(file.path, Duration.zero);
                      ref.read(playlistProvider.notifier).addItem(
                            PlaylistItem(path: file.path, title: file.title),
                            playImmediately: true,
                          );
                    } else if (val == 'queue') {
                      ref.read(playlistProvider.notifier).addItem(
                            PlaylistItem(path: file.path, title: file.title),
                            playImmediately: false,
                          );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Added to playlist: ${file.title}'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    } else if (val == 'copy') {
                      final sm = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: file.path));
                      sm.showSnackBar(
                        const SnackBar(
                          content: Text('File path copied to clipboard'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'play',
                      height: 32,
                      child: Row(
                        children: [
                          const Icon(Icons.play_arrow_rounded, size: 16, color: AppTheme.accent),
                          const SizedBox(width: 8),
                          Text('Play Now', style: TextStyle(fontSize: 12.5, color: textPrimary)),
                        ],
                      ),
                    ),
                    if (savedPos.inSeconds > 5)
                      PopupMenuItem(
                        value: 'restart',
                        height: 32,
                        child: Row(
                          children: [
                            Icon(Icons.replay_rounded, size: 15, color: textSecondary),
                            const SizedBox(width: 8),
                            Text('Play from Start', style: TextStyle(fontSize: 12.5, color: textPrimary)),
                          ],
                        ),
                      ),
                    PopupMenuItem(
                      value: 'queue',
                      height: 32,
                      child: Row(
                        children: [
                          Icon(Icons.playlist_add_rounded, size: 16, color: textSecondary),
                          const SizedBox(width: 8),
                          Text('Add to Queue', style: TextStyle(fontSize: 12.5, color: textPrimary)),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(height: 1),
                    PopupMenuItem(
                      value: 'copy',
                      height: 32,
                      child: Row(
                        children: [
                          Icon(Icons.content_copy_rounded, size: 15, color: textSecondary),
                          const SizedBox(width: 8),
                          Text('Copy Path', style: TextStyle(fontSize: 12.5, color: textPrimary)),
                        ],
                      ),
                    ),
                  ],
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Icon(Icons.more_vert, size: 20, color: textSecondary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallbackThumb() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF141620), Color(0xFF090A0F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accent.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/app_icon.png',
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'AURA CINEMA',
              style: AppTheme.caption.copyWith(
                fontSize: 9.5,
                letterSpacing: 1.4,
                color: Colors.white38,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyLibraryView() {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final textPrimary = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final borderCol = isDark ? AppTheme.glassBorder : AppTheme.lightGlassBorder;
    final cardBg = isDark
        ? const Color(0xFF0F1420).withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.35);

    final isAndroidWithoutPerm = Platform.isAndroid && !_hasStoragePermission;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: FrostedGlass(
          borderRadius: 24,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
          blur: 36,
          fillColor: cardBg,
          borderColor: borderCol,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppTheme.auraGradient,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accent.withValues(alpha: 0.45),
                        blurRadius: 28,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      isAndroidWithoutPerm ? Icons.folder_special_rounded : Icons.movie_rounded,
                      size: 34,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  isAndroidWithoutPerm
                      ? 'Direct Storage Access (VLC Mode)'
                      : 'No Videos Found',
                  textAlign: TextAlign.center,
                  style: AppTheme.headline.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    letterSpacing: -0.3,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  isAndroidWithoutPerm
                      ? 'Android blocks folder picking for privacy reasons. Enable "All files access" so Aura Player can automatically find and display all videos from WhatsApp, Camera, Downloads and SD Cards without manual folder selection.'
                      : 'No videos were found in standard phone storage locations. Import a video folder or individual files to begin watching.',
                  textAlign: TextAlign.center,
                  style: AppTheme.caption.copyWith(color: textSecondary, height: 1.45, fontSize: 12.5),
                ),
                const SizedBox(height: 24),
                if (isAndroidWithoutPerm) ...[
                  ElevatedButton.icon(
                    onPressed: () async {
                      await MobileStorageService.requestStoragePermission();
                    },
                    icon: const Icon(Icons.security_rounded, size: 18),
                    label: const Text('Grant All Files Access'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: const Color(0xFF04131F),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                      textStyle: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _importFolder,
                      icon: const Icon(Icons.create_new_folder_rounded, size: 16),
                      label: const Text('Import Folder'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: borderCol),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _importFiles,
                      icon: Icon(Icons.add_rounded, size: 16, color: textPrimary),
                      label: Text('Add Media Files', style: TextStyle(color: textPrimary)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: borderCol),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
}
