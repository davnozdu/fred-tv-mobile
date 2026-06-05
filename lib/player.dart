import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:open_tv/backend/sql.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/models/id_data.dart';
import 'package:open_tv/models/media_type.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkvideo;
import 'package:open_tv/models/settings.dart';
import 'package:open_tv/select_dialog.dart';

class _ControlAction {
  final IconData icon;
  final VoidCallback onTap;
  const _ControlAction(this.icon, this.onTap);
}

class Player extends StatefulWidget {
  final Channel channel;
  final Settings settings;
  const Player({super.key, required this.channel, required this.settings});
  @override
  State<StatefulWidget> createState() => _PlayerState();
}

class _PlayerState extends State<Player> {
  late mk.Player player = mk.Player();
  late mkvideo.VideoController videoController = mkvideo.VideoController(
    player,
  );
  late final GlobalKey<VideoState> key = GlobalKey<VideoState>();
  bool exiting = false;
  bool fill = false;
  List<StreamSubscription> subscriptions = [];

  // Custom TV-friendly controls overlay
  bool _controlsVisible = false;
  int _focusedIndex = 2;
  bool _isPlaying = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _hideTimer;
  final FocusNode _focusNode = FocusNode();

  bool get _isLive => widget.channel.mediaType == MediaType.livestream;

  @override
  void initState() {
    super.initState();
    mk.MediaKit.ensureInitialized();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    initAsync();
  }

  Future<void> initAsync() async {
    player.setPlaylistMode(mk.PlaylistMode.none);
    await setMpvOptions();
    final seconds = widget.channel.mediaType == MediaType.movie
        ? await Sql.getPosition(widget.channel.id!)
        : null;
    await _startPlayback(seconds != null ? Duration(seconds: seconds) : null);
    subscriptions.add(
      player.stream.completed.listen((completed) {
        if (completed) onDisconnect();
      }),
    );
    subscriptions.add(
      player.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      }),
    );
    subscriptions.add(
      player.stream.position.listen((position) {
        if (mounted) setState(() => _position = position);
      }),
    );
    subscriptions.add(
      player.stream.duration.listen((duration) {
        if (mounted) setState(() => _duration = duration);
      }),
    );
  }

  Future<void> setMpvOptions() async {
    if (player.platform is! mk.NativePlayer) return;
    final native = player.platform as mk.NativePlayer;
    // Аппаратное декодирование (HD/4K без рывков на ТВ-боксах),
    // auto-safe откатывается на софт, если HW недоступен.
    await native.setProperty('hwdec', 'auto-safe');
    if (widget.channel.mediaType == MediaType.livestream &&
        widget.settings.lowLatency) {
      // Минимальная задержка ценой буфера.
      await native.setProperty('profile', 'low-latency');
    } else {
      // Буферизация для стабильности (особенно HD).
      final secs = widget.settings.bufferSeconds;
      await native.setProperty('cache', 'yes');
      await native.setProperty('cache-secs', '$secs');
      await native.setProperty('demuxer-readahead-secs', '$secs');
      await native.setProperty('demuxer-max-bytes', '64MiB');
      await native.setProperty('demuxer-max-back-bytes', '32MiB');
    }
  }

  void onDisconnect() async {
    if (!mounted || exiting) return;
    if (widget.channel.mediaType == MediaType.livestream) {
      debugPrint("Live stream dropped/error. Attempting to reconnect...");
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || exiting) return;
      await _startPlayback(null);
    }
  }

  Future<void> _startPlayback(Duration? startPosition) async {
    while (true) {
      if (!mounted || exiting) return;
      try {
        final headers = await Sql.getChannelHeaders(widget.channel.id!);
        await player.open(
          mk.Media(
            widget.channel.url!,
            start: startPosition,
            httpHeaders: headers != null
                ? {
                    if (headers.referrer != null) "Referer": headers.referrer!,
                    if (headers.httpOrigin != null)
                      "Origin": headers.httpOrigin!,
                    if (headers.userAgent != null)
                      "User-Agent": headers.userAgent!,
                  }
                : null,
          ),
        );
        return;
      } catch (e) {
        debugPrint("Playback failed: $e. Retrying in 2s...");
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _focusNode.dispose();
    for (final s in subscriptions) s.cancel();
    player.dispose();
    super.dispose();
  }

  Future<void> openSubtitlesModal() async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => SelectDialog(
        title: "Select subtitles",
        action: (id) async {
          player.setSubtitleTrack(player.state.tracks.subtitle[id]);
          Navigator.of(context).pop();
        },
        data: player.state.tracks.subtitle
            .asMap()
            .entries
            .map(
              (entry) => IdData(
                id: entry.key,
                data: entry.value.language != null
                    ? "${entry.value.language} - ${entry.value.id}"
                    : entry.value.id,
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> openAudioModal() async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => SelectDialog(
        title: "Select audio",
        action: (id) async {
          player.setAudioTrack(player.state.tracks.audio[id]);
          Navigator.of(context).pop();
        },
        data: player.state.tracks.audio
            .asMap()
            .entries
            .map(
              (entry) => IdData(
                id: entry.key,
                data:
                    entry.value.title ?? entry.value.language ?? entry.value.id,
              ),
            )
            .toList(),
      ),
    );
  }

  List<_ControlAction> get _controls => [
    _ControlAction(Icons.replay_30, () => _seekRelative(-30)),
    _ControlAction(Icons.replay_5, () => _seekRelative(-5)),
    _ControlAction(
      _isPlaying ? Icons.pause : Icons.play_arrow,
      () => player.playOrPause(),
    ),
    _ControlAction(Icons.forward_5, () => _seekRelative(5)),
    _ControlAction(Icons.forward_30, () => _seekRelative(30)),
    _ControlAction(Icons.audiotrack, openAudioModal),
    _ControlAction(Icons.subtitles, openSubtitlesModal),
    _ControlAction(Icons.aspect_ratio, toggleZoom),
  ];

  void _seekRelative(int seconds) {
    var target = _position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (_duration > Duration.zero && target > _duration) target = _duration;
    player.seek(target);
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _resetHideTimer();
  }

  void _hideControls() {
    _hideTimer?.cancel();
    setState(() => _controlsVisible = false);
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = event.logicalKey;
    final controls = _controls;
    if (!_controlsVisible) {
      if (k == LogicalKeyboardKey.select ||
          k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.arrowUp ||
          k == LogicalKeyboardKey.arrowDown ||
          k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowRight ||
          k == LogicalKeyboardKey.mediaPlayPause) {
        _showControls();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      setState(() => _focusedIndex = (_focusedIndex - 1).clamp(0, controls.length - 1));
      _resetHideTimer();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      setState(() => _focusedIndex = (_focusedIndex + 1).clamp(0, controls.length - 1));
      _resetHideTimer();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      controls[_focusedIndex].onTap();
      _resetHideTimer();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      _resetHideTimer();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_controlsVisible) {
          _hideControls();
        } else {
          onExit();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _onKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _controlsVisible ? _hideControls() : _showControls(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Video(
                  key: key,
                  controller: videoController,
                  controls: NoVideoControls,
                  onExitFullscreen: () async => onExit(),
                ),
                _buildOverlay(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    return IgnorePointer(
      ignoring: !_controlsVisible,
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Stack(
          children: [
            // Top bar: back + channel name
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: onExit,
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.channel.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Bottom bar: progress + control buttons
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 32, 16, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildProgress(),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _buildControlButtons(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress() {
    if (_isLive) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
          SizedBox(width: 6),
          Text(
            "LIVE",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }
    final total = _duration.inMilliseconds == 0 ? 1 : _duration.inMilliseconds;
    final value = (_position.inMilliseconds / total).clamp(0.0, 1.0);
    return Row(
      children: [
        Text(
          _format(_position),
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.blue),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _format(_duration),
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ],
    );
  }

  List<Widget> _buildControlButtons() {
    final controls = _controls;
    return List.generate(controls.length, (i) {
      final focused = _controlsVisible && _focusedIndex == i;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Container(
          decoration: BoxDecoration(
            color: focused ? Colors.white24 : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: focused ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: IconButton(
            onPressed: () {
              setState(() => _focusedIndex = i);
              controls[i].onTap();
              _resetHideTimer();
            },
            icon: Icon(controls[i].icon, color: Colors.white, size: 30),
          ),
        ),
      );
    });
  }

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? "$h:$m:$s" : "$m:$s";
  }

  void onExit() async {
    if (exiting) return;
    exiting = true;
    if (widget.channel.mediaType == MediaType.movie) {
      Sql.setPosition(widget.channel.id!, player.state.position.inSeconds);
    }
    Navigator.of(context).pop();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void toggleZoom() {
    final videoAspectRatio = player.state.width! / player.state.height!;
    final deviceAspectRatio = MediaQuery.of(context).size.aspectRatio;
    key.currentState!.update(
      aspectRatio: fill ? videoAspectRatio : deviceAspectRatio,
    );
    setState(() {
      fill = !fill;
    });
  }
}
