import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../../player/player_controller.dart';
import '../../player/track_formatters.dart';
import '../../theme/app_theme.dart';
import '../modals/online_subtitles_modal.dart';

class AudioSubtitleSheet extends StatefulWidget {
  final AuraPlayerWrapper playerWrapper;

  const AudioSubtitleSheet({super.key, required this.playerWrapper});

  static Future<void> show(BuildContext context, AuraPlayerWrapper wrapper) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AudioSubtitleSheet(playerWrapper: wrapper),
    );
  }

  @override
  State<AudioSubtitleSheet> createState() => _AudioSubtitleSheetState();
}

class _AudioSubtitleSheetState extends State<AudioSubtitleSheet> {
  Future<void> _pickSubtitle() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'ass', 'vtt', 'sub'],
    );
    if (res != null && res.files.single.path != null) {
      await widget.playerWrapper.loadExternalSubtitle(res.files.single.path!);
      if (mounted) Navigator.of(context).pop();
    }
  }

  String _formatDelay(Duration d) {
    final ms = d.inMilliseconds;
    if (ms == 0) return '0.0 s';
    final sign = ms > 0 ? '+' : '';
    return '$sign${(ms / 1000).toStringAsFixed(1)} s';
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.playerWrapper.player;
    final tracks = player.state.tracks;
    final currentAudio = player.state.track.audio;
    final currentSub = player.state.track.subtitle;
    final screenH = MediaQuery.of(context).size.height;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1420).withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: Colors.white12),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle pill
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune_rounded, size: 20, color: AppTheme.accent),
                  const SizedBox(width: 10),
                  Text('Audio & Subtitle Tracks', style: AppTheme.body.copyWith(fontWeight: FontWeight.w700, fontSize: 16)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 22, color: AppTheme.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),

                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Audio Tracks
                        Text('AUDIO TRACK', style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        if (tracks.audio.isEmpty)
                          Text('No alternate audio tracks available', style: AppTheme.caption)
                        else
                          ...tracks.audio.map((t) {
                            final isSelected = t.id == currentAudio.id;
                            final label = TrackFormatters.formatAudioTrack(t);
                            return _trackTile(
                              title: label,
                              isSelected: isSelected,
                              onTap: () {
                                widget.playerWrapper.setAudioTrack(t);
                                setState(() {});
                              },
                            );
                          }),

                        const SizedBox(height: 20),
                        const Divider(color: AppTheme.glassBorder, height: 1),
                        const SizedBox(height: 16),

                        // Subtitle Tracks
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('SUBTITLES', style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600)),
                            Row(
                              children: [
                                InkWell(
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    OnlineSubtitlesModal.show(context, widget.playerWrapper);
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.cloud_download_rounded, size: 15, color: AppTheme.accentCyan),
                                        const SizedBox(width: 4),
                                        Text('Search Online', style: AppTheme.caption.copyWith(color: AppTheme.accentCyan, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: _pickSubtitle,
                                  borderRadius: BorderRadius.circular(6),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.add_rounded, size: 15, color: AppTheme.accent),
                                        const SizedBox(width: 4),
                                        Text('Add .srt', style: AppTheme.caption.copyWith(color: AppTheme.accent)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Subtitle Off Option
                        _trackTile(
                          title: 'Off',
                          isSelected: currentSub == SubtitleTrack.no(),
                          onTap: () {
                            widget.playerWrapper.setSubtitleTrack(SubtitleTrack.no());
                            setState(() {});
                          },
                        ),

                        // Subtitle Track List
                        ...tracks.subtitle.map((s) {
                          final isSelected = s.id == currentSub.id;
                          final label = TrackFormatters.formatSubtitleTrack(s);
                          return _trackTile(
                            title: label,
                            isSelected: isSelected,
                            onTap: () {
                              widget.playerWrapper.setSubtitleTrack(s);
                              setState(() {});
                            },
                          );
                        }),

                        const SizedBox(height: 20),
                        const Divider(color: AppTheme.glassBorder, height: 1),
                        const SizedBox(height: 16),

                        // Subtitle Delay
                        Text('SUBTITLE DELAY', style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDelay(widget.playerWrapper.subtitleDelay),
                              style: AppTheme.body.copyWith(fontWeight: FontWeight.w600, color: AppTheme.accent),
                            ),
                            Row(
                              children: [
                                _delayButton('-0.5s', () {
                                  widget.playerWrapper.adjustSubtitleDelay(const Duration(milliseconds: -500));
                                  setState(() {});
                                }),
                                const SizedBox(width: 6),
                                _delayButton('-0.1s', () {
                                  widget.playerWrapper.adjustSubtitleDelay(const Duration(milliseconds: -100));
                                  setState(() {});
                                }),
                                const SizedBox(width: 6),
                                _delayButton('Reset', () {
                                  widget.playerWrapper.subtitleDelay = Duration.zero;
                                  setState(() {});
                                }),
                                const SizedBox(width: 6),
                                _delayButton('+0.1s', () {
                                  widget.playerWrapper.adjustSubtitleDelay(const Duration(milliseconds: 100));
                                  setState(() {});
                                }),
                                const SizedBox(width: 6),
                                _delayButton('+0.5s', () {
                                  widget.playerWrapper.adjustSubtitleDelay(const Duration(milliseconds: 500));
                                  setState(() {});
                                }),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _trackTile({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTheme.bodySmall.copyWith(
                  color: isSelected ? AppTheme.accent : AppTheme.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_rounded, size: 16, color: AppTheme.accent),
          ],
        ),
      ),
    );
  }

  Widget _delayButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surfaceSecondary,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Text(label, style: AppTheme.caption.copyWith(color: AppTheme.textPrimary)),
      ),
    );
  }
}
