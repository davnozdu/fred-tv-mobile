import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_tv/l10n/strings.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/models/settings.dart';
import 'package:open_tv/player.dart';

/// Shown on autostart while the network is still coming up after a reboot.
/// Waits until the device has an IP *and* the stream source is reachable, then
/// opens the player — so the user doesn't stare at a bare spinner with no
/// network. Falls through after a timeout so it never hangs forever.
class BootWaitScreen extends StatefulWidget {
  final Channel channel;
  final Settings settings;
  final List<Channel>? playlist;
  const BootWaitScreen({
    super.key,
    required this.channel,
    required this.settings,
    this.playlist,
  });

  @override
  State<BootWaitScreen> createState() => _BootWaitScreenState();
}

class _BootWaitScreenState extends State<BootWaitScreen> {
  Timer? _timer;
  final DateTime _start = DateTime.now();
  static const _timeout = Duration(seconds: 45);

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (!mounted) return;
    final timedOut = DateTime.now().difference(_start) > _timeout;
    final ready = timedOut || await _networkReady();
    if (!mounted) return;
    if (ready) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => Player(
            channel: widget.channel,
            settings: widget.settings,
            playlist: widget.playlist,
          ),
        ),
      );
    } else {
      _timer = Timer(const Duration(seconds: 1), _check);
    }
  }

  // Ready = the device has a real (non-loopback) IPv4 address AND the stream
  // host accepts a TCP connection (so DNS/route/source are all actually up).
  Future<bool> _networkReady() async {
    bool hasIp = false;
    try {
      final ifaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      hasIp = ifaces.any((i) => i.addresses.isNotEmpty);
    } catch (_) {}
    if (!hasIp) return false;
    try {
      final uri = Uri.parse(widget.channel.url ?? '');
      final host = uri.host;
      if (host.isEmpty) return true; // can't probe — having an IP is enough
      final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      final socket =
          await Socket.connect(host, port, timeout: const Duration(seconds: 3));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                S.of(context).waitingForNetwork,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
