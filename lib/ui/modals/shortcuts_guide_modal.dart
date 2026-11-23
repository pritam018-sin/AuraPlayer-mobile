import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/frosted_glass.dart';

class ShortcutsGuideModal extends StatelessWidget {
  const ShortcutsGuideModal({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.50),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: const ShortcutsGuideModal(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: FrostedGlass(
          borderRadius: 24,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          blur: 36,
          fillColor: isDark
              ? const Color(0xFF0F121C).withValues(alpha: 0.92)
              : Colors.white.withValues(alpha: 0.94),
          borderColor: isDark ? AppTheme.glassBorder : AppTheme.lightGlassBorder,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440, maxHeight: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Modal Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: AppTheme.auraGradient,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.touch_app_rounded, size: 20, color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Touch Gestures Guide',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: textPrimary,
                              ),
                            ),
                            Text(
                              'Master AuraPlayer Mobile Controls',
                              style: TextStyle(
                                fontSize: 11,
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 20, color: textSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Gesture List
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader('SWIPE GESTURES', Icons.swipe_rounded),
                        _gestureRow(
                          icon: Icons.brightness_6_rounded,
                          title: 'Left Screen Vertical Swipe',
                          desc: 'Slide up/down on left half to adjust screen brightness smoothly.',
                          isDark: isDark,
                        ),
                        _gestureRow(
                          icon: Icons.volume_up_rounded,
                          title: 'Right Screen Vertical Swipe',
                          desc: 'Slide up/down on right half for volume with 150% boost indicator.',
                          isDark: isDark,
                        ),
                        _gestureRow(
                          icon: Icons.swap_horiz_rounded,
                          title: 'Horizontal Drag (Center)',
                          desc: 'Swipe left/right anywhere to scrub with live timestamp bubble.',
                          isDark: isDark,
                        ),
                        const SizedBox(height: 14),

                        _sectionHeader('TAP & HOLD CONTROLS', Icons.touch_app_outlined),
                        _gestureRow(
                          icon: Icons.fast_forward_rounded,
                          title: 'Long Press & Hold',
                          desc: 'Press and hold anywhere on video for instant 2X Fast Forward.',
                          isDark: isDark,
                        ),
                        _gestureRow(
                          icon: Icons.double_arrow_rounded,
                          title: 'Double Tap Sides',
                          desc: 'Double tap left side to rewind 10s, right side to forward 10s.',
                          isDark: isDark,
                        ),
                        _gestureRow(
                          icon: Icons.play_arrow_rounded,
                          title: 'Single Tap / Double Tap Center',
                          desc: 'Single tap toggles HUD controls; double tap in center plays/pauses.',
                          isDark: isDark,
                        ),
                        const SizedBox(height: 14),

                        _sectionHeader('MOBILE CINEMA FEATURES', Icons.movie_filter_rounded),
                        _gestureRow(
                          icon: Icons.lock_outline_rounded,
                          title: 'Screen Touch Lock',
                          desc: 'Lock screen to prevent accidental touches while relaxing in bed.',
                          isDark: isDark,
                        ),
                        _gestureRow(
                          icon: Icons.aspect_ratio_rounded,
                          title: 'Aspect Ratio & Zoom to Fill',
                          desc: 'Cycle between Original Fit, Crop to Fill (19.5:9), and Stretch.',
                          isDark: isDark,
                        ),
                        _gestureRow(
                          icon: Icons.picture_in_picture_alt_rounded,
                          title: 'Native Android PiP Mode',
                          desc: 'Swipe Home while playing to keep watching in floating window.',
                          isDark: isDark,
                        ),
                        _gestureRow(
                          icon: Icons.camera_alt_rounded,
                          title: 'Gallery Frame Capture',
                          desc: 'Snapshots are saved directly to Pictures/AuraPlayer in your Gallery.',
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentCyan,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.accentCyan),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.accentCyan,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _gestureRow({
    required IconData icon,
    required String title,
    required String desc,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0x3322D3EE) : const Color(0x220284C7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: isDark ? AppTheme.accentCyan : const Color(0xFF0284C7)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
