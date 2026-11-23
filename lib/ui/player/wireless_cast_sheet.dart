import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../player/player_controller.dart';
import '../../services/native_player_bridge.dart';
import '../../theme/app_theme.dart';

class WirelessCastSheet extends StatefulWidget {
  final AuraPlayerWrapper playerWrapper;

  const WirelessCastSheet({super.key, required this.playerWrapper});

  static Future<void> show(BuildContext context, AuraPlayerWrapper playerWrapper) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WirelessCastSheet(playerWrapper: playerWrapper),
    );
  }

  @override
  State<WirelessCastSheet> createState() => _WirelessCastSheetState();
}

class _WirelessCastSheetState extends State<WirelessCastSheet> {
  static HttpServer? _activeServer;
  static String? _activeServedPath;
  static int _serverPort = 8899;

  String? _localWifiIp;
  String? _castUrl;
  bool _isServing = false;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _setupCastUrl();
  }

  Future<void> _setupCastUrl() async {
    final currentPath = widget.playerWrapper.currentFilePath ?? '';
    final isOnline = currentPath.startsWith('http://') || currentPath.startsWith('https://');

    if (isOnline) {
      if (mounted) {
        setState(() {
          _castUrl = currentPath;
        });
      }
      return;
    }

    // Local file - detect Wi-Fi IP and start local streaming server
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && (addr.address.startsWith('192.168.') || addr.address.startsWith('10.') || addr.address.startsWith('172.'))) {
            _localWifiIp = addr.address;
            break;
          }
        }
        if (_localWifiIp != null) break;
      }
    } catch (_) {}

    _localWifiIp ??= '192.168.1.100';

    if (currentPath.isNotEmpty && File(currentPath).existsSync()) {
      await _startLocalServer(currentPath);
    }
  }

  Future<void> _startLocalServer(String filePath) async {
    if (_activeServer != null && _activeServedPath == filePath) {
      if (mounted) {
        setState(() {
          _isServing = true;
          _castUrl = 'http://$_localWifiIp:$_serverPort/video';
        });
      }
      return;
    }

    try {
      await _activeServer?.close(force: true);
      _activeServer = await HttpServer.bind(InternetAddress.anyIPv4, _serverPort);
      _activeServedPath = filePath;
      _isServing = true;

      _activeServer!.listen((HttpRequest request) async {
        final file = File(filePath);
        if (!await file.exists()) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        final fileLength = await file.length();
        final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        request.response.headers.set(HttpHeaders.contentTypeHeader, 'video/mp4');
        request.response.headers.set('Access-Control-Allow-Origin', '*');

        if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
          final parts = rangeHeader.substring(6).split('-');
          final start = int.tryParse(parts[0]) ?? 0;
          final end = parts.length > 1 && parts[1].isNotEmpty ? int.tryParse(parts[1]) ?? (fileLength - 1) : fileLength - 1;

          final contentLength = end - start + 1;
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$fileLength');
          request.response.headers.set(HttpHeaders.contentLengthHeader, contentLength.toString());

          final stream = file.openRead(start, end + 1);
          await request.response.addStream(stream);
        } else {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(HttpHeaders.contentLengthHeader, fileLength.toString());
          await request.response.addStream(file.openRead());
        }

        await request.response.close();
      });

      if (mounted) {
        setState(() {
          _castUrl = 'http://$_localWifiIp:$_serverPort/video';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _castUrl = 'file://$filePath';
        });
      }
    }
  }

  void _copyToClipboard() {
    if (_castUrl == null) return;
    Clipboard.setData(ClipboardData(text: _castUrl!));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.playerWrapper.currentTitle ?? 'Video';
    final currentPath = widget.playerWrapper.currentFilePath ?? '';
    final screenH = MediaQuery.of(context).size.height;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F1420),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Colors.white12, width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom > 0
            ? MediaQuery.of(context).padding.bottom + 16
            : 24,
      ),
      constraints: BoxConstraints(maxHeight: screenH * 0.85),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Handle
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
            const SizedBox(height: 16),

            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.accentCyan.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.cast_connected_rounded, color: AppTheme.accentCyan, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Wireless Cast & Screen Share',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Option 1: Native Android Screen Cast / Smart View (Miracast / TVs)
            _castOptionCard(
              icon: Icons.tv_rounded,
              iconColor: const Color(0xFF38BDF8),
              title: 'Screen Cast / Smart View',
              subtitle: 'Connect wirelessly to Samsung, LG, Fire TV, Roku, or Android TV via Miracast / Wireless Display',
              badge: 'DIRECT TV',
              onTap: () {
                Navigator.of(context).pop();
                NativePlayerBridge.openCastSettings();
              },
            ),
            const SizedBox(height: 10),

            // Option 2: Cast Video to External Cast Apps (DLNA / Chromecast)
            _castOptionCard(
              icon: Icons.cast_rounded,
              iconColor: const Color(0xFF10B981),
              title: 'Cast via Apps (Chromecast / DLNA)',
              subtitle: 'Send stream to Web Video Caster, BubbleUPnP, Google Home, VLC or Smart TV apps',
              badge: 'DLNA / CAST',
              onTap: () {
                Navigator.of(context).pop();
                final castTarget = _castUrl ?? currentPath;
                NativePlayerBridge.castMediaToApp(
                  url: castTarget,
                  title: title,
                  mimeType: 'video/*',
                );
              },
            ),
            const SizedBox(height: 10),

            // Option 3: Wi-Fi Browser Stream & Link Sharing
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.wifi_tethering_rounded, color: Colors.amber, size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Wi-Fi Browser Playback',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'ANY BROWSER',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Open this link in any TV browser, PC, or tablet connected to the same Wi-Fi to watch immediately in full quality:',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_castUrl != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.40),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _castUrl!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF38BDF8),
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: _copyToClipboard,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _copied ? const Color(0xFF10B981) : AppTheme.accentCyan.withValues(alpha: 0.20),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                                    size: 13,
                                    color: _copied ? Colors.white : AppTheme.accentCyan,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _copied ? 'Copied' : 'Copy',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _copied ? Colors.white : AppTheme.accentCyan,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Quick TV Pairing Tips
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.white54, size: 16),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ensure your TV and phone are connected to the same Wi-Fi network for optimal discovery.',
                      style: TextStyle(fontSize: 11, color: Colors.white60, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _castOptionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String badge,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: iconColor,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }
}
