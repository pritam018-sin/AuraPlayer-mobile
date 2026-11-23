import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../player/player_controller.dart';
import '../../services/native_player_bridge.dart';
import '../../state/player_provider.dart';
import '../../theme/app_theme.dart';
import 'audio_sub_sheet.dart';
import 'aura_loading_overlay.dart';
import 'context_menu.dart';
import 'floating_controls.dart';
import 'video_glassy_menu.dart';
import 'wireless_cast_sheet.dart';

class VideoSurface extends ConsumerStatefulWidget {
  final AuraPlayerWrapper playerWrapper;

  const VideoSurface({super.key, required this.playerWrapper});

  @override
  ConsumerState<VideoSurface> createState() => _VideoSurfaceState();
}

class _VideoSurfaceState extends ConsumerState<VideoSurface> {
  Timer? _hideTimer;
  bool _controlsVisible = true;
  final FocusNode _focusNode = FocusNode();

  // YouTube-style double-tap quick seek state
  int? _seekRippleAmount;
  bool _seekRippleLeft = true;
  Timer? _seekRippleTimer;

  // VLC Mobile Gestures: Brightness (Left Swipe) & Volume (Right Swipe)
  double _screenBrightness = 1.0;
  bool _showBrightnessIndicator = false;
  Timer? _brightnessTimer;

  bool _showVolumeIndicator = false;
  double _currentVolumeDisplay = 100.0;
  Timer? _volumeTimer;
  bool? _isDraggingLeftHalf;

  // Horizontal Fine-Scrubbing
  bool _isHorizontalScrubbing = false;
  Duration _scrubStartPosition = Duration.zero;
  int _scrubDeltaSeconds = 0;

  // Screen Touch Lock (Child / Bed mode)
  bool _isScreenLocked = false;
  bool _showLockOverlay = false;
  Timer? _lockTimer;

  // Aspect Ratio Cycling (0: Fit, 1: Crop to Fill 20:9, 2: 16:9 Stretch)
  int _aspectRatioIndex = 0;
  String? _aspectRatioHud;
  Timer? _aspectRatioTimer;

  // Press & Hold 2X Speed
  bool _isSpeedLocked2X = false;
  double? _originalRate;

  // Pinch to Zoom
  double _videoScale = 1.0;
  Offset _videoPanOffset = Offset.zero;
  double _baseScale = 1.0;
  Offset _basePanOffset = Offset.zero;
  String? _zoomHudText;
  Timer? _zoomHudTimer;

  bool _isScaleZooming = false;
  bool _isScaleScrubbing = false;
  bool _isScaleVerticalAdjust = false;
  Offset _scaleStartFocalPoint = Offset.zero;

  void _triggerZoomHud(double scale) {
    _zoomHudTimer?.cancel();
    setState(() {
      _zoomHudText = 'Zoom ${scale.toStringAsFixed(1)}x';
    });
    _zoomHudTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _zoomHudText = null);
    });
  }

  void _resetZoom() {
    setState(() {
      _videoScale = 1.0;
      _videoPanOffset = Offset.zero;
      _zoomHudText = 'Zoom 1.0x (Fit)';
    });
    HapticFeedback.lightImpact();
    _zoomHudTimer?.cancel();
    _zoomHudTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _zoomHudText = null);
    });
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

  BoxFit get _videoBoxFit {
    switch (_aspectRatioIndex) {
      case 1:
        return BoxFit.cover; // Zoom / Crop to fill tall mobile screens
      case 2:
        return BoxFit.fill; // Stretch
      case 0:
      default:
        return BoxFit.contain; // Original fit with black bars
    }
  }

  void _cycleAspectRatio() {
    setState(() {
      _aspectRatioIndex = (_aspectRatioIndex + 1) % 3;
      switch (_aspectRatioIndex) {
        case 0:
          _aspectRatioHud = 'ORIGINAL FIT';
          break;
        case 1:
          _aspectRatioHud = 'CROP TO FILL (ZOOM 20:9)';
          break;
        case 2:
          _aspectRatioHud = 'STRETCH (16:9)';
          break;
      }
    });

    HapticFeedback.lightImpact();
    _aspectRatioTimer?.cancel();
    _aspectRatioTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _aspectRatioHud = null);
    });
    _onUserActivity();
  }

  void _triggerSeekRipple(int seconds, bool isLeft) {
    _seekRippleTimer?.cancel();
    setState(() {
      _seekRippleAmount = seconds;
      _seekRippleLeft = isLeft;
    });
    _seekRippleTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() => _seekRippleAmount = null);
      }
    });
  }

  void _handleScaleStart(ScaleStartDetails details, double screenW) {
    if (_isScreenLocked) return;
    _baseScale = _videoScale;
    _basePanOffset = _videoPanOffset;
    _scaleStartFocalPoint = details.localFocalPoint;
    _isScaleZooming = details.pointerCount >= 2;
    _isScaleScrubbing = false;
    _isScaleVerticalAdjust = false;

    if (details.pointerCount == 1 && _videoScale <= 1.05) {
      _isDraggingLeftHalf = details.localFocalPoint.dx < (screenW / 2);
    }
    _hideTimer?.cancel();
  }

  void _handleScaleUpdate(ScaleUpdateDetails details, double screenW, double screenH) {
    if (_isScreenLocked) return;

    // 1. PINCH-TO-ZOOM (2 or more fingers, or active pinch)
    if (details.pointerCount >= 2 || _isScaleZooming) {
      _isScaleZooming = true;
      final newScale = (_baseScale * details.scale).clamp(1.0, 4.5);
      setState(() {
        _videoScale = newScale;
        if (newScale > 1.05) {
          _videoPanOffset = _basePanOffset + details.focalPointDelta;
        } else {
          _videoPanOffset = Offset.zero;
        }
      });
      _triggerZoomHud(newScale);
      _onUserActivity();
      return;
    }

    // 2. ZOOMED PANNING (1 finger while video is zoomed in)
    if (_videoScale > 1.05) {
      setState(() {
        _videoPanOffset += details.focalPointDelta;
      });
      _onUserActivity();
      return;
    }

    // 3. NORMAL 1-FINGER GESTURES (Horizontal Seek Scrub vs Vertical Brightness/Volume)
    final totalDx = details.localFocalPoint.dx - _scaleStartFocalPoint.dx;
    final totalDy = details.localFocalPoint.dy - _scaleStartFocalPoint.dy;

    // Lock gesture direction once movement exceeds threshold (8px)
    if (!_isScaleScrubbing && !_isScaleVerticalAdjust) {
      if (totalDx.abs() > 8 && totalDx.abs() > totalDy.abs() * 1.3) {
        _isScaleScrubbing = true;
        _scrubStartPosition = widget.playerWrapper.player.state.position;
        _scrubDeltaSeconds = 0;
        setState(() => _isHorizontalScrubbing = true);
      } else if (totalDy.abs() > 8) {
        _isScaleVerticalAdjust = true;
      }
    }

    if (_isScaleScrubbing) {
      // Horizontal fine scrubbing
      final totalDuration = widget.playerWrapper.player.state.duration;
      final dragDx = details.focalPointDelta.dx;
      final scale = totalDuration.inSeconds > 3600
          ? 0.45
          : (totalDuration.inSeconds > 600 ? 0.30 : 0.18);
      setState(() {
        _scrubDeltaSeconds += (dragDx * scale).round();
      });
    } else if (_isScaleVerticalAdjust) {
      final delta = -details.focalPointDelta.dy;
      if (_isDraggingLeftHalf == true) {
        // Left half: Real Android Hardware Screen Brightness
        final change = delta / (screenH * 0.55);
        final newBrightness = (_screenBrightness + change).clamp(0.01, 1.0);
        setState(() {
          _screenBrightness = newBrightness;
          _showBrightnessIndicator = true;
        });
        NativePlayerBridge.setScreenBrightness(newBrightness);
        _brightnessTimer?.cancel();
        _brightnessTimer = Timer(const Duration(milliseconds: 1000), () {
          if (mounted) setState(() => _showBrightnessIndicator = false);
        });
      } else {
        // Right half: Real Android System Media Volume & Boost
        final change = (delta / (screenH * 0.55)) * 100.0;
        final newVol = (_currentVolumeDisplay + change).clamp(0.0, 150.0);
        setState(() {
          _currentVolumeDisplay = newVol;
          _showVolumeIndicator = true;
        });

        if (newVol <= 100.0) {
          widget.playerWrapper.setVolume(100.0);
          NativePlayerBridge.setSystemVolume(newVol);
        } else {
          NativePlayerBridge.setSystemVolume(100.0);
          widget.playerWrapper.setVolume(newVol);
        }

        _volumeTimer?.cancel();
        _volumeTimer = Timer(const Duration(milliseconds: 1000), () {
          if (mounted) setState(() => _showVolumeIndicator = false);
        });
      }
    }
    _onUserActivity();
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _isScaleZooming = false;
    _isDraggingLeftHalf = null;

    if (_videoScale < 1.05) {
      setState(() {
        _videoScale = 1.0;
        _videoPanOffset = Offset.zero;
      });
    }

    if (_isHorizontalScrubbing) {
      final totalDuration = widget.playerWrapper.player.state.duration;
      final targetMs = (_scrubStartPosition.inMilliseconds + _scrubDeltaSeconds * 1000)
          .clamp(0, totalDuration.inMilliseconds);
      final target = Duration(milliseconds: targetMs);
      widget.playerWrapper.seek(target);
      HapticFeedback.mediumImpact();
      setState(() {
        _isHorizontalScrubbing = false;
        _scrubDeltaSeconds = 0;
      });
    }

    _isScaleScrubbing = false;
    _isScaleVerticalAdjust = false;
    _startHideTimer();
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    if (_isScreenLocked) return;
    _originalRate = widget.playerWrapper.player.state.rate;
    widget.playerWrapper.setRate(2.0);
    HapticFeedback.lightImpact();
    setState(() {
      _isSpeedLocked2X = true;
    });
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    if (_isSpeedLocked2X) {
      widget.playerWrapper.setRate(_originalRate ?? 1.0);
      setState(() {
        _isSpeedLocked2X = false;
      });
    }
  }

  void _handleLongPressCancel() {
    if (_isSpeedLocked2X) {
      widget.playerWrapper.setRate(_originalRate ?? 1.0);
      setState(() {
        _isSpeedLocked2X = false;
      });
    }
  }

  void _toggleScreenLock() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isScreenLocked = !_isScreenLocked;
      if (_isScreenLocked) {
        _controlsVisible = false;
        _showLockOverlay = true;
        _startLockOverlayTimer();
      } else {
        _showLockOverlay = false;
        _controlsVisible = true;
        _startHideTimer();
      }
    });
  }

  void _startLockOverlayTimer() {
    _lockTimer?.cancel();
    _lockTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _showLockOverlay = false);
    });
  }

  @override
  void initState() {
    super.initState();
    _startHideTimer();
    NativePlayerBridge.getScreenBrightness().then((b) {
      if (mounted) setState(() => _screenBrightness = b);
    });
    NativePlayerBridge.getSystemVolume().then((v) {
      if (mounted) setState(() => _currentVolumeDisplay = v);
    });
    if (widget.playerWrapper.isLiveStream) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  @override
  void dispose() {
    NativePlayerBridge.resetScreenBrightness();
    _zoomHudTimer?.cancel();
    _seekRippleTimer?.cancel();
    _brightnessTimer?.cancel();
    _volumeTimer?.cancel();
    _hideTimer?.cancel();
    _lockTimer?.cancel();
    _aspectRatioTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 2800), () {
      if (mounted) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _onUserActivity() {
    if (_isScreenLocked) {
      setState(() => _showLockOverlay = true);
      _startLockOverlayTimer();
      return;
    }
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _startHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    final windowState = ref.watch(windowControlsProvider);

    // 1. Android Native Picture-in-Picture Mode Check
    return ValueListenableBuilder<bool>(
      valueListenable: NativePlayerBridge.isNativePipNotifier,
      builder: (context, isNativePip, _) {
        if (isNativePip) {
          // Minimal pure video surface for Native OS PiP window
          return Center(
            child: Video(
              controller: widget.playerWrapper.videoController,
              controls: NoVideoControls,
              fit: _videoBoxFit,
            ),
          );
        }

        return Stack(
          children: [
            // MediaKit Video Surface filling window
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final screenW = constraints.maxWidth;
                  final screenH = constraints.maxHeight;

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (_isScreenLocked) {
                        setState(() => _showLockOverlay = true);
                        _startLockOverlayTimer();
                        return;
                      }
                      // Tap toggles controls visibility
                      setState(() => _controlsVisible = !_controlsVisible);
                      if (_controlsVisible) _startHideTimer();
                    },
                    onDoubleTapDown: (details) {
                      if (_isScreenLocked) return;
                      if (_videoScale > 1.05) {
                        _resetZoom();
                        _onUserActivity();
                        return;
                      }
                      final x = details.localPosition.dx;
                      if (x < screenW * 0.35) {
                        widget.playerWrapper.seekRelative(const Duration(seconds: -10));
                        _triggerSeekRipple(10, true);
                      } else if (x > screenW * 0.65) {
                        widget.playerWrapper.seekRelative(const Duration(seconds: 10));
                        _triggerSeekRipple(10, false);
                      } else {
                        widget.playerWrapper.playOrPause();
                      }
                      _onUserActivity();
                    },
                    onScaleStart: (details) => _handleScaleStart(details, screenW),
                    onScaleUpdate: (details) => _handleScaleUpdate(details, screenW, screenH),
                    onScaleEnd: (details) => _handleScaleEnd(details),
                    onLongPressStart: _handleLongPressStart,
                    onLongPressEnd: _handleLongPressEnd,
                    onLongPressCancel: _handleLongPressCancel,
                    onSecondaryTapDown: (details) {
                      if (!_isScreenLocked) {
                        VideoContextMenu.show(
                          context,
                          details.globalPosition,
                          widget.playerWrapper,
                          ref,
                        );
                      }
                    },
                    child: Center(
                      child: ClipRect(
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..translate(_videoPanOffset.dx, _videoPanOffset.dy)
                            ..scale(_videoScale),
                          child: ValueListenableBuilder<int>(
                            valueListenable: widget.playerWrapper.subtitleConfigRevision,
                            builder: (context, rev, child) {
                              return Video(
                                controller: widget.playerWrapper.videoController,
                                controls: NoVideoControls,
                                fit: _videoBoxFit,
                                subtitleViewConfiguration: widget.playerWrapper.subtitleViewConfiguration,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Smooth Night Screen Dimmer only for ultra-low backlight (< 8%)
            if (_screenBrightness < 0.08)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withValues(
                      alpha: (1.0 - (_screenBrightness / 0.08)).clamp(0.0, 0.70),
                    ),
                  ),
                ),
              ),

            // Cinematic AuraPlayer Logo Loading & Buffering Overlay
            Positioned.fill(
              child: AuraLoadingOverlay(
                playerWrapper: widget.playerWrapper,
              ),
            ),

            // Double-Tap Quick Seek Visual Ripples (Tiny Frosted Glass Capsule)
            if (_seekRippleAmount != null)
              Positioned(
                top: 0,
                bottom: 0,
                left: _seekRippleLeft ? 36 : null,
                right: !_seekRippleLeft ? 36 : null,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 0.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _seekRippleLeft ? Icons.replay_10_rounded : Icons.forward_10_rounded,
                              size: 14,
                              color: AppTheme.accentCyan,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${_seekRippleLeft ? '-' : '+'}${_seekRippleAmount}s',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // VLC-style Left Side Brightness HUD Indicator (Tiny Frosted Glass Capsule)
            if (_showBrightnessIndicator)
              Positioned(
                left: 28,
                top: 0,
                bottom: 0,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 0.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _screenBrightness > 0.65
                                  ? Icons.brightness_7_rounded
                                  : (_screenBrightness > 0.35
                                      ? Icons.brightness_6_rounded
                                      : Icons.brightness_4_rounded),
                              color: Colors.amberAccent,
                              size: 15,
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: 3.5,
                              height: 65,
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: 3.5,
                                height: 65 * _screenBrightness,
                                decoration: BoxDecoration(
                                  color: Colors.amberAccent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${(_screenBrightness * 100).toInt()}%',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // VLC-style Right Side Volume HUD Indicator (Tiny Frosted Glass Capsule)
            if (_showVolumeIndicator)
              Positioned(
                right: 28,
                top: 0,
                bottom: 0,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 0.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _currentVolumeDisplay == 0
                                  ? Icons.volume_off_rounded
                                  : (_currentVolumeDisplay > 100
                                      ? Icons.volume_up_rounded
                                      : Icons.volume_down_rounded),
                              color: _currentVolumeDisplay > 100 ? Colors.orangeAccent : AppTheme.accentCyan,
                              size: 15,
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: 3.5,
                              height: 65,
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: 3.5,
                                height: (65 * (_currentVolumeDisplay / 150.0)).clamp(0.0, 65.0),
                                decoration: BoxDecoration(
                                  color: _currentVolumeDisplay > 100 ? Colors.orangeAccent : AppTheme.accentCyan,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_currentVolumeDisplay.toInt()}%',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: _currentVolumeDisplay > 100 ? Colors.orangeAccent : Colors.white,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Horizontal Fine-Scrubbing Tiny Frosted Glass Capsule
            if (_isHorizontalScrubbing)
              Center(
                child: Builder(
                  builder: (context) {
                    final totalDuration = widget.playerWrapper.player.state.duration;
                    final targetMs = (_scrubStartPosition.inMilliseconds + _scrubDeltaSeconds * 1000)
                        .clamp(0, totalDuration.inMilliseconds);
                    final targetPos = Duration(milliseconds: targetMs);
                    final isPositive = _scrubDeltaSeconds >= 0;
                    final color = isPositive ? AppTheme.accentCyan : const Color(0xFFFBBF24);

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.52),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                              width: 0.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isPositive ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
                                color: color,
                                size: 15,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${isPositive ? '+' : ''}${_scrubDeltaSeconds}s',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Container(width: 1, height: 12, color: Colors.white24),
                              ),
                              Text(
                                '${_formatDuration(targetPos)} / ${_formatDuration(totalDuration)}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // Aspect Ratio HUD Pill (Tiny Frosted Glass Capsule)
            if (_aspectRatioHud != null)
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.52),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 14,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.aspect_ratio_rounded, color: AppTheme.accentCyan, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            _aspectRatioHud!,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Press & Hold 2X Speed HUD Pill (Tiny Frosted Glass Capsule)
            if (_isSpeedLocked2X)
              Positioned(
                top: MediaQuery.of(context).padding.top > 0
                    ? MediaQuery.of(context).padding.top + 48
                    : 48,
                left: 0,
                right: 0,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 0.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.fast_forward_rounded,
                              color: AppTheme.accentCyan,
                              size: 14,
                            ),
                            SizedBox(width: 5),
                            Text(
                              '2X Speed',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Screen Touch Lock Floating Unlock Overlay (Tiny Frosted Glass Capsule)
            if (_isScreenLocked && _showLockOverlay)
              Positioned(
                top: MediaQuery.of(context).padding.top > 0
                    ? MediaQuery.of(context).padding.top + 16
                    : 16,
                left: 16,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _toggleScreenLock,
                    borderRadius: BorderRadius.circular(20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.52),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                              width: 0.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 14,
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_rounded, color: AppTheme.accentCyan, size: 13),
                              SizedBox(width: 5),
                              Text(
                                'UNLOCK',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Pinch Zoom HUD Pill (Tiny Frosted Glass Capsule)
            if (_zoomHudText != null)
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.52),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 14,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.zoom_in_rounded, color: AppTheme.accentCyan, size: 15),
                          const SizedBox(width: 6),
                          Text(
                            _zoomHudText!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Top Bar & Bottom Floating Controls (Normal Window & Fullscreen)
            if (!_isScreenLocked && !windowState.isMiniMode) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildVideoTopBar(),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: FloatingControls(
                  playerWrapper: widget.playerWrapper,
                  isVisible: _controlsVisible,
                  onLockRequested: _toggleScreenLock,
                ),
              ),
            ] else if (!_isScreenLocked && windowState.isMiniMode) ...[
              // Dedicated In-App Mini Window Overlay
              Positioned.fill(
                child: _buildMiniPiPOverlay(windowState),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildVideoTopBar() {
    final isLive = widget.playerWrapper.isLiveStream;
    final title = widget.playerWrapper.currentTitle ??
        (isLive ? 'Live Stream' : 'Video');
    final topPadding = MediaQuery.of(context).padding.top > 0
        ? MediaQuery.of(context).padding.top + 6
        : 14.0;
    final isNarrow = MediaQuery.of(context).size.width < 500;

    return AnimatedOpacity(
      opacity: _controlsVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.85),
                Colors.black.withValues(alpha: 0.40),
                Colors.transparent,
              ],
            ),
          ),
          padding: EdgeInsets.fromLTRB(14, topPadding, 14, 16),
          child: Row(
            children: [
              // Back Button to exit video & return to library
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    ref.read(playlistProvider.notifier).stopAndClose();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.headline.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.90),
                            blurRadius: 12,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    if (isLive)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'LIVE BROADCAST',
                              style: AppTheme.caption.copyWith(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFFEF4444),
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              if (!isNarrow) ...[
                // Screen Lock Button in wide landscape
                _topBarIconButton(
                  icon: Icons.lock_open_rounded,
                  tooltip: 'Lock Screen',
                  onTap: _toggleScreenLock,
                ),
                const SizedBox(width: 4),
              ],

              // Aspect Ratio Cycling Button
              _topBarIconButton(
                icon: Icons.aspect_ratio_rounded,
                tooltip: 'Aspect Ratio',
                onTap: _cycleAspectRatio,
              ),
              const SizedBox(width: 4),

              // Native Android Picture-in-Picture Button
              _topBarIconButton(
                icon: Icons.picture_in_picture_alt_rounded,
                tooltip: 'Picture in Picture',
                onTap: () => NativePlayerBridge.enterPip(),
              ),
              const SizedBox(width: 4),

              // Wireless Cast Button (Miracast / DLNA / Chromecast / Web share)
              _topBarIconButton(
                icon: Icons.cast_rounded,
                tooltip: 'Wireless Cast',
                onTap: () => WirelessCastSheet.show(context, widget.playerWrapper),
              ),
              const SizedBox(width: 4),

              // Audio / Subtitles button
              _topBarIconButton(
                icon: Icons.closed_caption_rounded,
                tooltip: 'Subtitles & Audio',
                onTap: () => AudioSubtitleSheet.show(context, widget.playerWrapper),
              ),
              const SizedBox(width: 4),

              if (!isNarrow) ...[
                // Screen Rotation / Fullscreen button in wide landscape
                _topBarIconButton(
                  icon: Icons.screen_rotation_rounded,
                  tooltip: 'Rotate Screen',
                  onTap: () {
                    if (isLive) {
                      SystemChrome.setPreferredOrientations([
                        DeviceOrientation.landscapeLeft,
                        DeviceOrientation.landscapeRight,
                      ]);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Live TV is locked to Landscape Cinema mode'),
                          duration: Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    } else {
                      ref.read(windowControlsProvider.notifier).toggleFullscreen();
                    }
                  },
                ),
                const SizedBox(width: 4),
              ],

              // 3-dots More Options Menu
              _topBarIconButton(
                icon: Icons.more_vert_rounded,
                tooltip: 'More Settings',
                onTap: () {
                  VideoGlassyMenu.show(
                    context: context,
                    playerWrapper: widget.playerWrapper,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBarIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              color: Colors.white,
              size: 21,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniPiPOverlay(WindowControlsState windowState) {
    final player = widget.playerWrapper.player;
    final isLive = widget.playerWrapper.isLiveStream;
    final title = widget.playerWrapper.currentTitle ?? (isLive ? 'Live Stream' : 'Video');

    return AnimatedOpacity(
      opacity: _controlsVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.8),
              Colors.black.withValues(alpha: 0.15),
              Colors.black.withValues(alpha: 0.85),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top Bar: Drag Title + Controls
            Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    gradient: AppTheme.auraGradient,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Image.asset('assets/app_icon.png', width: 14, height: 14),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                if (isLive) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                // Exit PiP / Expand Button
                Tooltip(
                  message: 'Expand Window',
                  child: InkWell(
                    onTap: () => ref.read(windowControlsProvider.notifier).toggleMiniMode(),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.open_in_full_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Close Button
                Tooltip(
                  message: 'Close',
                  child: InkWell(
                    onTap: () => ref.read(playlistProvider.notifier).stopAndClose(),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),

            // Center Controls: Rewind 10s, Hero Play/Pause, Forward 10s
            StreamBuilder<bool>(
              stream: player.stream.playing,
              builder: (context, snapshot) {
                final isPlaying = snapshot.data ?? player.state.playing;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    InkWell(
                      onTap: () {
                        widget.playerWrapper.seekRelative(const Duration(seconds: -10));
                        _onUserActivity();
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.replay_10_rounded, size: 18, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 18),
                    GestureDetector(
                      onTap: () {
                        widget.playerWrapper.playOrPause();
                        _onUserActivity();
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: AppTheme.auraGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accent.withValues(alpha: 0.45),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    InkWell(
                      onTap: () {
                        widget.playerWrapper.seekRelative(const Duration(seconds: 10));
                        _onUserActivity();
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.forward_10_rounded, size: 18, color: Colors.white),
                      ),
                    ),
                  ],
                );
              },
            ),

            // Bottom Bar: Progress Indicator & Mute
            Row(
              children: [
                Expanded(
                  child: StreamBuilder<Duration>(
                    stream: player.stream.position,
                    builder: (context, snapshot) {
                      final pos = snapshot.data ?? player.state.position;
                      final total = player.state.duration;
                      final frac = total.inMilliseconds > 0
                          ? (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
                          : 0.0;
                      return Row(
                        children: [
                          Text(
                            isLive ? 'LIVE' : _formatDuration(pos),
                            style: AppTheme.caption.copyWith(fontSize: 10, color: Colors.white70),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: isLive ? 1.0 : frac,
                                backgroundColor: Colors.white12,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isLive ? const Color(0xFFEF4444) : AppTheme.accent,
                                ),
                                minHeight: 3,
                              ),
                            ),
                          ),
                          if (!isLive) ...[
                            const SizedBox(width: 8),
                            Text(
                              _formatDuration(total),
                              style: AppTheme.caption.copyWith(fontSize: 10, color: Colors.white70),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () {
                    widget.playerWrapper.toggleMute();
                    _onUserActivity();
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: StreamBuilder<double>(
                    stream: player.stream.volume,
                    builder: (context, snapshot) {
                      final vol = snapshot.data ?? player.state.volume;
                      return Icon(
                        vol == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        size: 16,
                        color: Colors.white70,
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
