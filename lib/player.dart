import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_tv/backend/sql.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/models/id_data.dart';
import 'package:open_tv/models/media_type.dart';
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
  BetterPlayerController? _controller;
  BetterPlayerDataSource? _dataSource;
  bool exiting = false;

  // Custom TV-friendly controls overlay
  bool _controlsVisible = false;
  int _focusedIndex = 2;
  bool _isPlaying = true;
  late bool _isFav = widget.channel.favorite;
  Timer? _hideTimer;
  Timer? _ticker;
  final FocusNode _focusNode = FocusNode();

  bool get _isLive => widget.channel.mediaType == MediaType.livestream;

  Duration get _position =>
      _controller?.videoPlayerController?.value.position ?? Duration.zero;
  Duration get _duration =>
      _controller?.videoPlayerController?.value.duration ?? Duration.zero;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _init();
    // Refresh the progress bar/time while the panel is visible.
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _controlsVisible) setState(() {});
    });
  }

  Future<void> _init() async {
    final headers = await Sql.getChannelHeaders(widget.channel.id!);
    final hdr = <String, String>{
      if (headers?.referrer != null) "Referer": headers!.referrer!,
      if (headers?.httpOrigin != null) "Origin": headers!.httpOrigin!,
      if (headers?.userAgent != null) "User-Agent": headers!.userAgent!,
    };
    _dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      widget.channel.url!,
      liveStream: _isLive,
      headers: hdr.isNotEmpty ? hdr : null,
      bufferingConfiguration: _bufferingConfig(),
    );
    final controller = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: true,
        fit: BoxFit.contain,
        handleLifecycle: true,
        autoDispose: false,
        allowedScreenSleep: false,
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          showControls: false,
        ),
      ),
    );
    controller.addEventsListener(_onEvent);
    await controller.setupDataSource(_dataSource!);
    if (!mounted) {
      controller.dispose(forceDispose: true);
      return;
    }
    if (widget.channel.mediaType == MediaType.movie) {
      final secs = await Sql.getPosition(widget.channel.id!);
      if (secs != null && secs > 0) {
        await controller.seekTo(Duration(seconds: secs));
      }
    }
    setState(() => _controller = controller);
  }

  BetterPlayerBufferingConfiguration _bufferingConfig() {
    if (widget.settings.lowLatency && _isLive) {
      return const BetterPlayerBufferingConfiguration(
        minBufferMs: 5000,
        maxBufferMs: 15000,
        bufferForPlaybackMs: 1000,
        bufferForPlaybackAfterRebufferMs: 2000,
      );
    }
    final ms = widget.settings.bufferSeconds * 1000;
    return BetterPlayerBufferingConfiguration(
      minBufferMs: ms,
      maxBufferMs: (ms * 2).clamp(30000, 600000),
      bufferForPlaybackMs: 2500,
      bufferForPlaybackAfterRebufferMs: 5000,
    );
  }

  void _onEvent(BetterPlayerEvent event) {
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.play:
        if (mounted) setState(() => _isPlaying = true);
        break;
      case BetterPlayerEventType.pause:
        if (mounted) setState(() => _isPlaying = false);
        break;
      case BetterPlayerEventType.finished:
      case BetterPlayerEventType.exception:
        _onDisconnect();
        break;
      default:
        break;
    }
  }

  // Live streams should reconnect automatically on error/drop.
  Future<void> _onDisconnect() async {
    if (!mounted || exiting || !_isLive || _dataSource == null) return;
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted || exiting) return;
    try {
      await _controller?.setupDataSource(_dataSource!);
    } catch (_) {}
  }

  Future<void> _toggleFavorite() async {
    final value = !_isFav;
    await Sql.favoriteChannel(widget.channel.id!, value);
    widget.channel.favorite = value;
    if (mounted) setState(() => _isFav = value);
  }

  List<_ControlAction> get _controls => [
    _ControlAction(Icons.replay_30, () => _seekRelative(-30)),
    _ControlAction(Icons.replay_5, () => _seekRelative(-5)),
    _ControlAction(
      _isPlaying ? Icons.pause : Icons.play_arrow,
      _togglePlay,
    ),
    _ControlAction(Icons.forward_5, () => _seekRelative(5)),
    _ControlAction(Icons.forward_30, () => _seekRelative(30)),
    _ControlAction(
      _isFav ? Icons.favorite : Icons.favorite_border,
      _toggleFavorite,
    ),
    _ControlAction(Icons.audiotrack, _openAudioModal),
  ];

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    if (c.isPlaying() ?? false) {
      c.pause();
    } else {
      c.play();
    }
  }

  void _seekRelative(int seconds) {
    final c = _controller;
    if (c == null) return;
    var target = _position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    final dur = _duration;
    if (dur > Duration.zero && target > dur) target = dur;
    c.seekTo(target);
  }

  Future<void> _openAudioModal() async {
    final tracks = _controller?.betterPlayerAsmsAudioTracks ?? [];
    if (tracks.isEmpty) return;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => SelectDialog(
        title: "Select audio",
        action: (id) {
          _controller?.setAudioTrack(tracks[id]);
          Navigator.of(ctx).pop();
        },
        data: tracks
            .asMap()
            .entries
            .map(
              (e) => IdData(
                id: e.key,
                data: e.value.label ?? e.value.language ?? "Audio ${e.key + 1}",
              ),
            )
            .toList(),
      ),
    );
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
      setState(
        () => _focusedIndex = (_focusedIndex - 1).clamp(0, controls.length - 1),
      );
      _resetHideTimer();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      setState(
        () => _focusedIndex = (_focusedIndex + 1).clamp(0, controls.length - 1),
      );
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
                Container(color: Colors.black),
                if (_controller != null)
                  BetterPlayer(controller: _controller!)
                else
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
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
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
    final c = _controller;
    if (widget.channel.mediaType == MediaType.movie &&
        c?.videoPlayerController != null) {
      Sql.setPosition(
        widget.channel.id!,
        c!.videoPlayerController!.value.position.inSeconds,
      );
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

  @override
  void dispose() {
    _hideTimer?.cancel();
    _ticker?.cancel();
    _focusNode.dispose();
    _controller?.dispose(forceDispose: true);
    super.dispose();
  }
}
