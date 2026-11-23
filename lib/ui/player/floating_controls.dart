import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../player/player_controller.dart';
import '../../state/player_provider.dart';
import '../../theme/app_theme.dart';
import 'seek_bar.dart';

class FloatingControls extends ConsumerStatefulWidget {
  final AuraPlayerWrapper playerWrapper;
  final bool isVisible;
  final VoidCallback? onLockRequested;

  const FloatingControls({
    super.key,
    required this.playerWrapper,
    required this.isVisible,
    this.onLockRequested,
  });

  @override
  ConsumerState<FloatingControls> createState() => _FloatingControlsState();
}

class _FloatingControlsState extends ConsumerState<FloatingControls> {
  bool _showRemainingTime = false;
  Duration? _draggedSeekPosition;

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _cycleSpeed() {
    final cur = widget.playerWrapper.player.state.rate;
    final speeds = [1.0, 1.25, 1.5, 2.0, 0.75];
    int nextIdx = 0;
    for (int i = 0; i < speeds.length; i++) {
      if ((cur - speeds[i]).abs() < 0.1) {
        nextIdx = (i + 1) % speeds.length;
        break;
      }
    }
    widget.playerWrapper.setRate(speeds[nextIdx]);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.playerWrapper.player;
    final playlist = ref.watch(playlistProvider);
    final playlistNotifier = ref.read(playlistProvider.notifier);
    final windowNotifier = ref.read(windowControlsProvider.notifier);

    return StreamBuilder<bool>(
      stream: player.stream.playing,
      initialData: player.state.playing,
      builder: (context, playingSnap) {
        final isPlaying = playingSnap.data ?? false;

        return StreamBuilder<Duration>(
          stream: player.stream.position,
          initialData: player.state.position,
          builder: (context, posSnap) {
            final position = posSnap.data ?? Duration.zero;

            return StreamBuilder<Duration>(
              stream: player.stream.duration,
              initialData: player.state.duration,
              builder: (context, durSnap) {
                final duration = durSnap.data ?? Duration.zero;

                return StreamBuilder<Duration>(
                  stream: player.stream.buffer,
                  initialData: player.state.buffer,
                  builder: (context, bufSnap) {
                    final buffer = bufSnap.data ?? Duration.zero;

                    return StreamBuilder<double>(
                      stream: player.stream.volume,
                      initialData: player.state.volume,
                      builder: (context, volSnap) {
                        final volume = volSnap.data ?? 100.0;

                        return StreamBuilder<double>(
                          stream: player.stream.rate,
                          initialData: player.state.rate,
                          builder: (context, rateSnap) {
                            final currentRate = rateSnap.data ?? 1.0;
                            final isLive = widget.playerWrapper.isLiveStream;

                            final effectivePos = _draggedSeekPosition ?? position;
                            final remaining = (duration - effectivePos).isNegative
                                ? Duration.zero
                                : (duration - effectivePos);

                            final timeDisplay = isLive
                                ? 'LIVE'
                                : (_showRemainingTime
                                    ? '-${_formatDuration(remaining)}'
                                    : '${_formatDuration(effectivePos)} / ${_formatDuration(duration)}');

                            return AnimatedOpacity(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              opacity: widget.isVisible ? 1.0 : 0.0,
                              child: IgnorePointer(
                                ignoring: !widget.isVisible,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [
                                        Colors.black.withValues(alpha: 0.85),
                                        Colors.black.withValues(alpha: 0.40),
                                        Colors.transparent,
                                      ],
                                      stops: const [0.0, 0.60, 1.0],
                                    ),
                                  ),
                                  padding: EdgeInsets.fromLTRB(
                                    12,
                                    16,
                                    12,
                                    MediaQuery.of(context).padding.bottom > 0
                                        ? MediaQuery.of(context).padding.bottom + 8
                                        : 14,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // 1. Time display above seek bar (Left Elapsed, Right Duration/Remaining)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (isLive) ...[
                                                  Container(
                                                    width: 6,
                                                    height: 6,
                                                    decoration: const BoxDecoration(
                                                      color: Color(0xFFEF4444),
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 5),
                                                ],
                                                Text(
                                                  isLive ? 'LIVE' : _formatDuration(effectivePos),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                    fontSize: 11.5,
                                                    letterSpacing: 0.2,
                                                    fontFeatures: [FontFeature.tabularFigures()],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (!isLive)
                                              InkWell(
                                                onTap: () => setState(() => _showRemainingTime = !_showRemainingTime),
                                                borderRadius: BorderRadius.circular(4),
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                  child: Text(
                                                    _showRemainingTime ? '-${_formatDuration(remaining)}' : _formatDuration(duration),
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w700,
                                                      color: Colors.white70,
                                                      fontSize: 11.5,
                                                      letterSpacing: 0.2,
                                                      fontFeatures: [FontFeature.tabularFigures()],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),

                                      // 2. Touch-friendly Seek Bar
                                      CustomSeekBar(
                                        position: position,
                                        duration: duration,
                                        buffer: buffer,
                                        isLive: isLive,
                                        onDragChanged: (d) {
                                          setState(() => _draggedSeekPosition = d);
                                        },
                                        onSeek: (pos) => widget.playerWrapper.seek(pos),
                                      ),

                                      const SizedBox(height: 8),

                                      // 3. Ergonomic Mobile Control Strip (Never overflows)
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          // Left Toggles: Screen Lock & Speed
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (widget.onLockRequested != null) ...[
                                                _mobileActionButton(
                                                  icon: Icons.lock_open_rounded,
                                                  size: 20,
                                                  onTap: widget.onLockRequested!,
                                                ),
                                                const SizedBox(width: 4),
                                              ],
                                              InkWell(
                                                onTap: _cycleSpeed,
                                                borderRadius: BorderRadius.circular(8),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: currentRate != 1.0
                                                        ? AppTheme.accent.withValues(alpha: 0.25)
                                                        : Colors.white.withValues(alpha: 0.10),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: currentRate != 1.0 ? AppTheme.accent : Colors.white12,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    '${currentRate.toStringAsFixed(currentRate.truncateToDouble() == currentRate ? 0 : 2)}x',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w700,
                                                      color: currentRate != 1.0 ? AppTheme.accent : Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),

                                          // Center Playback Controls: Prev (if multi), -10s, Hero Play/Pause, +10s, Next (if multi)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (playlist.items.length > 1) ...[
                                                _mobileActionButton(
                                                  icon: Icons.skip_previous_rounded,
                                                  size: 20,
                                                  enabled: playlist.hasPrev,
                                                  onTap: () => playlistNotifier.prev(),
                                                ),
                                                const SizedBox(width: 2),
                                              ],
                                              _mobileActionButton(
                                                icon: Icons.replay_10_rounded,
                                                size: 22,
                                                onTap: () => widget.playerWrapper.seekRelative(const Duration(seconds: -10)),
                                              ),
                                              const SizedBox(width: 8),

                                              // Primary Play/Pause Hero Button
                                              GestureDetector(
                                                onTap: () => widget.playerWrapper.playOrPause(),
                                                child: Container(
                                                  width: 46,
                                                  height: 46,
                                                  decoration: BoxDecoration(
                                                    gradient: AppTheme.auraGradient,
                                                    shape: BoxShape.circle,
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: AppTheme.accent.withValues(alpha: 0.5),
                                                        blurRadius: 14,
                                                        spreadRadius: 1,
                                                        offset: const Offset(0, 2),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Center(
                                                    child: Icon(
                                                      isPlaying
                                                          ? Icons.pause_rounded
                                                          : Icons.play_arrow_rounded,
                                                      size: 28,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),

                                              _mobileActionButton(
                                                icon: Icons.forward_10_rounded,
                                                size: 22,
                                                onTap: () => widget.playerWrapper.seekRelative(const Duration(seconds: 10)),
                                              ),
                                              if (playlist.items.length > 1) ...[
                                                const SizedBox(width: 2),
                                                _mobileActionButton(
                                                  icon: Icons.skip_next_rounded,
                                                  size: 20,
                                                  enabled: playlist.hasNext,
                                                  onTap: () => playlistNotifier.next(),
                                                ),
                                              ],
                                            ],
                                          ),

                                          // Right Toggles: Mute & Rotate/Fullscreen
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _mobileActionButton(
                                                icon: volume == 0
                                                    ? Icons.volume_off_rounded
                                                    : (volume < 50
                                                        ? Icons.volume_down_rounded
                                                        : Icons.volume_up_rounded),
                                                size: 20,
                                                onTap: () => widget.playerWrapper.toggleMute(),
                                              ),
                                              const SizedBox(width: 4),
                                              _mobileActionButton(
                                                icon: Icons.fullscreen_rounded,
                                                size: 22,
                                                onTap: () => windowNotifier.toggleFullscreen(),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _mobileActionButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 22,
    bool enabled = true,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: size,
            color: enabled ? Colors.white : Colors.white24,
          ),
        ),
      ),
    );
  }
}
