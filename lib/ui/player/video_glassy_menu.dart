import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../player/player_controller.dart';
import '../../services/native_player_bridge.dart';
import '../../state/player_provider.dart';
import '../../theme/app_theme.dart';
import 'audio_sub_sheet.dart';
import 'wireless_cast_sheet.dart';

class VideoGlassyMenu extends ConsumerStatefulWidget {
  final AuraPlayerWrapper playerWrapper;

  const VideoGlassyMenu({
    super.key,
    required this.playerWrapper,
    Offset? position,
  });

  static Future<void> show({
    required BuildContext context,
    Offset? position,
    required AuraPlayerWrapper playerWrapper,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VideoGlassyMenu(playerWrapper: playerWrapper),
    );
  }

  @override
  ConsumerState<VideoGlassyMenu> createState() => _VideoGlassyMenuState();
}

class _VideoGlassyMenuState extends ConsumerState<VideoGlassyMenu> {
  final List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  final List<String> _aspects = ['default', '16:9', '4:3', '21:9'];

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final windowNotifier = ref.read(windowControlsProvider.notifier);
    final playlistNotifier = ref.read(playlistProvider.notifier);
    final screenH = MediaQuery.of(context).size.height;

    final currentRate = widget.playerWrapper.player.state.rate;
    final currentAspect = widget.playerWrapper.currentAspectRatio ?? 'default';
    final isPlaying = widget.playerWrapper.player.state.playing;

    final textPrimary = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final dividerColor = isDark ? Colors.white12 : Colors.black12;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1420).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom > 0
            ? MediaQuery.of(context).padding.bottom + 12
            : 24,
      ),
      constraints: BoxConstraints(maxHeight: screenH * 0.85),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune_rounded, size: 20, color: AppTheme.accentCyan),
                    const SizedBox(width: 8),
                    Text(
                      'Video Controls & Settings',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 22, color: textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            Divider(height: 20, thickness: 0.8, color: dividerColor),

            // 1. Playback Speed Row
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.speed_rounded, size: 18, color: AppTheme.accent),
                        const SizedBox(width: 8),
                        Text(
                          'Playback Speed',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: textPrimary),
                        ),
                      ],
                    ),
                    Text(
                      '${currentRate.toStringAsFixed(currentRate.truncateToDouble() == currentRate ? 0 : 2)}x',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: _speeds.map((rate) {
                    final isSelected = (currentRate - rate).abs() < 0.05;
                    return Expanded(
                      child: _pillButton(
                        label: '${rate.toStringAsFixed(rate.truncateToDouble() == rate ? 0 : 2)}x',
                        isSelected: isSelected,
                        isDark: isDark,
                        onTap: () {
                          widget.playerWrapper.setRate(rate);
                          setState(() {});
                        },
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),

            Divider(height: 24, thickness: 0.8, color: dividerColor),

            // 2. Aspect Ratio Row
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.aspect_ratio_rounded, size: 18, color: textSecondary),
                        const SizedBox(width: 8),
                        Text(
                          'Aspect Ratio',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: textPrimary),
                        ),
                      ],
                    ),
                    Text(
                      currentAspect == 'default' ? 'FIT SCREEN' : currentAspect.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accentCyan,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: _aspects.map((aspect) {
                    final isSelected = currentAspect.toLowerCase() == aspect.toLowerCase();
                    final label = aspect == 'default' ? 'Fit' : aspect;
                    return Expanded(
                      child: _pillButton(
                        label: label,
                        isSelected: isSelected,
                        isDark: isDark,
                        onTap: () {
                          widget.playerWrapper.setAspectRatio(aspect);
                          setState(() {});
                        },
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),

            Divider(height: 24, thickness: 0.8, color: dividerColor),

            // 3. Quick Action Menu Tiles
            _mobileMenuTile(
              icon: isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
              iconColor: AppTheme.accent,
              title: isPlaying ? 'Pause Playback' : 'Resume Playback',
              subtitle: 'Toggle play/pause state',
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              onTap: () {
                widget.playerWrapper.playOrPause();
                Navigator.of(context).pop();
              },
            ),

            _mobileMenuTile(
              icon: Icons.subtitles_rounded,
              iconColor: AppTheme.accentCyan,
              title: 'Audio Tracks & Subtitles',
              subtitle: 'Change audio language or load subtitle file',
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              onTap: () {
                Navigator.of(context).pop();
                AudioSubtitleSheet.show(context, widget.playerWrapper);
              },
            ),

            _mobileMenuTile(
              icon: Icons.cast_connected_rounded,
              iconColor: const Color(0xFF38BDF8),
              title: 'Wireless Cast to TV / Device',
              subtitle: 'Screen mirror (Miracast/Smart View), DLNA or Wi-Fi Browser Share',
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              onTap: () {
                Navigator.of(context).pop();
                WirelessCastSheet.show(context, widget.playerWrapper);
              },
            ),

            _mobileMenuTile(
              icon: Icons.picture_in_picture_alt_rounded,
              iconColor: AppTheme.accentCyan,
              title: 'Picture-in-Picture (PiP)',
              subtitle: 'Minimize video into floating native Android window',
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              onTap: () {
                Navigator.of(context).pop();
                NativePlayerBridge.enterPip();
              },
            ),

            _mobileMenuTile(
              icon: Icons.headphones_rounded,
              iconColor: const Color(0xFFA855F7),
              title: 'Background Audio Mode',
              subtitle: 'Keep playing audio when phone screen is turned off',
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              onTap: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.headphones_rounded, color: Color(0xFFA855F7), size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Background audio active. Playback will continue with screen locked.',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: const Color(0xFF131927),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFFA855F7), width: 0.8),
                    ),
                  ),
                );
              },
            ),

            _mobileMenuTile(
              icon: Icons.screen_rotation_rounded,
              iconColor: Colors.amber,
              title: 'Rotate Screen / Fullscreen',
              subtitle: 'Switch between portrait and landscape mode',
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              onTap: () {
                Navigator.of(context).pop();
                windowNotifier.toggleFullscreen();
              },
            ),

            _mobileMenuTile(
              icon: Icons.camera_alt_rounded,
              iconColor: Colors.tealAccent,
              title: 'Capture Frame Snapshot',
              subtitle: 'Save high-res still image from video',
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              onTap: () async {
                Navigator.of(context).pop();
                final path = await widget.playerWrapper.takeSnapshot();
                if (context.mounted && path != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Snapshot saved: ${path.split(RegExp(r'[/\\]')).last}'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),

            Divider(height: 20, thickness: 0.8, color: dividerColor),

            _mobileMenuTile(
              icon: Icons.stop_circle_rounded,
              iconColor: Colors.redAccent,
              title: 'Stop & Exit to Library',
              subtitle: 'Close video and return to library view',
              textPrimary: Colors.redAccent,
              textSecondary: Colors.redAccent.withValues(alpha: 0.7),
              onTap: () {
                Navigator.of(context).pop();
                playlistNotifier.stopAndClose();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _pillButton({
    required String label,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.accent.withValues(alpha: isDark ? 0.30 : 0.22)
                : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppTheme.accent : (isDark ? Colors.white12 : Colors.black12),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected
                  ? (isDark ? Colors.white : const Color(0xFF0284C7))
                  : (isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mobileMenuTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Color textPrimary,
    required Color textSecondary,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: textSecondary),
          ],
        ),
      ),
    );
  }
}
