import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_tv/backend/epg.dart';
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
  bool _archiveMode = false;
  EpgProgram? _currentProgram;
  int? _archiveStartEpoch;
  List<EpgProgram>? _programs;
  late bool _isFav = widget.channel.favorite;
  Timer? _hideTimer;
  Timer? _ticker;
  Timer? _watchdog;
  Duration _lastPos = Duration.zero;
  DateTime _lastProgress = DateTime.now();
  int _autoBufferSec = 20;
  final List<DateTime> _rebufferTimes = [];
  final FocusNode _focusNode = FocusNode();

  bool get _isLive => widget.channel.mediaType == MediaType.livestream;
  bool get _isMovie => widget.channel.mediaType == MediaType.movie;

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
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _controlsVisible) setState(() {});
    });
    // Watchdog: restart a stream that silently freezes (plays but position
    // stops advancing) — covers stalls that never raise an error event.
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) => _checkAlive());
  }

  void _checkAlive() {
    final c = _controller;
    if (c == null || exiting || _isMovie) return;
    // Only act on a real freeze — never fight a user-initiated pause.
    final playing = _isPlaying && (c.isPlaying() ?? false);
    final pos = c.videoPlayerController?.value.position ?? Duration.zero;
    if (!playing || pos != _lastPos) {
      _lastPos = pos;
      _lastProgress = DateTime.now();
      return;
    }
    if (DateTime.now().difference(_lastProgress) > const Duration(seconds: 5)) {
      _lastProgress = DateTime.now();
      _reconnect();
    }
  }

  Future<void> _reconnect() async {
    final ds = _dataSource;
    if (exiting || ds == null) return;
    try {
      // In archive, resume from the frozen point (not the program start).
      if (_archiveMode && _archiveStartEpoch != null) {
        final point = _archiveStartEpoch! + _position.inSeconds;
        final url = _timeshiftUrl(point);
        if (url != null) {
          _archiveStartEpoch = point;
          await _setup(url, true);
          return;
        }
      }
      // Rebuild via _setup so the (possibly grown) auto-buffer applies.
      await _setup(ds.url, ds.liveStream ?? false);
    } catch (_) {}
  }

  Future<void> _init() async {
    await _setup(widget.channel.url!, _isLive);
    if (widget.channel.mediaType == MediaType.movie) {
      final secs = await Sql.getPosition(widget.channel.id!);
      if (secs != null && secs > 0) {
        await _controller?.seekTo(Duration(seconds: secs));
      }
    }
  }

  Future<void> _setup(String url, bool live) async {
    final headers = await Sql.getChannelHeaders(widget.channel.id!);
    final hdr = <String, String>{
      if (headers?.referrer != null) "Referer": headers!.referrer!,
      if (headers?.httpOrigin != null) "Origin": headers!.httpOrigin!,
      if (headers?.userAgent != null) "User-Agent": headers!.userAgent!,
    };
    final ds = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      url,
      liveStream: live,
      headers: hdr.isNotEmpty ? hdr : null,
      bufferingConfiguration: _bufferingConfig(),
    );
    _dataSource = ds;
    var controller = _controller;
    if (controller == null) {
      controller = BetterPlayerController(
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
    }
    await controller.setupDataSource(ds);
    if (!mounted) {
      controller.dispose(forceDispose: true);
      return;
    }
    setState(() => _controller = controller);
  }

  BetterPlayerBufferingConfiguration _bufferingConfig() {
    if (widget.settings.lowLatency && _isLive && !_archiveMode) {
      return const BetterPlayerBufferingConfiguration(
        minBufferMs: 5000,
        maxBufferMs: 15000,
        bufferForPlaybackMs: 1000,
        bufferForPlaybackAfterRebufferMs: 2000,
      );
    }
    // bufferSeconds <= 0 means "Auto": start moderate, grow on repeated stalls.
    final configured = widget.settings.bufferSeconds;
    final sec = configured <= 0 ? _autoBufferSec : configured;
    final ms = sec * 1000;
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
        _lastProgress = DateTime.now();
        if (mounted) setState(() => _isPlaying = true);
        break;
      case BetterPlayerEventType.pause:
        if (mounted) setState(() => _isPlaying = false);
        break;
      case BetterPlayerEventType.bufferingStart:
        _onRebuffer();
        break;
      case BetterPlayerEventType.exception:
        _onDisconnect();
        break;
      case BetterPlayerEventType.finished:
        if (!_archiveMode) _onDisconnect();
        break;
      default:
        break;
    }
  }

  // Auto-buffer: grow the buffer when the stream stalls repeatedly.
  void _onRebuffer() {
    if (widget.settings.bufferSeconds > 0) return; // only in Auto mode
    final now = DateTime.now();
    _rebufferTimes.add(now);
    _rebufferTimes.removeWhere(
      (t) => now.difference(t) > const Duration(minutes: 2),
    );
    if (_rebufferTimes.length >= 3 && _autoBufferSec < 90) {
      _autoBufferSec = (_autoBufferSec + 15).clamp(20, 90);
      _rebufferTimes.clear();
    }
  }

  // Reconnect live/archive streams on error or hard drop (not movies).
  Future<void> _onDisconnect() async {
    if (!mounted || exiting || _isMovie || _dataSource == null) return;
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted || exiting) return;
    await _reconnect();
  }

  // ---------------------------------------------------------------------------
  // Archive (Flussonic catchup)
  // ---------------------------------------------------------------------------

  String? _streamRoot() {
    final base = widget.channel.url;
    if (base == null) return null;
    final q = base.indexOf('?');
    final clean = q >= 0 ? base.substring(0, q) : base;
    final idx = clean.lastIndexOf('/');
    if (idx <= 0) return null;
    return clean.substring(0, idx); // .../<channelId>
  }

  // Flussonic catchup: play from <utc> and continue through the archive
  // (timeshift). index-<from>-<dur> is ignored by this provider, but
  // index.m3u8?utc=<start>&lutc=<now> works.
  String? _timeshiftUrl(int utc) {
    final root = _streamRoot();
    if (root == null) return null;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    if (utc >= now) return null;
    return '$root/index.m3u8?utc=$utc&lutc=$now';
  }

  Future<void> _playLive() async {
    _archiveMode = false;
    _currentProgram = null;
    _archiveStartEpoch = null;
    await _setup(widget.channel.url!, true);
  }

  Future<void> _playArchive(EpgProgram p) async {
    final startEpoch = p.start.millisecondsSinceEpoch ~/ 1000;
    final url = _timeshiftUrl(startEpoch);
    if (url == null) return;
    _archiveMode = true;
    _currentProgram = p;
    _archiveStartEpoch = startEpoch;
    await _setup(url, true); // timeshift = live-style playlist
  }

  Future<void> _openArchiveMenu() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
    List<EpgProgram> programs = [];
    try {
      programs =
          _programs ?? await fetchPrograms(archiveEpgUrl, widget.channel.name);
      _programs = programs;
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close loading

    final now = DateTime.now().toUtc();
    final from = now.subtract(const Duration(days: 7));
    final past =
        programs
            .where((p) => p.start.isAfter(from) && p.start.isBefore(now))
            .toList()
          ..sort((a, b) => b.start.compareTo(a.start));

    if (past.isEmpty) {
      _toast("No archive programmes found for this channel");
      return;
    }
    await _showProgramSheet(past);
  }

  Future<void> _showProgramSheet(List<EpgProgram> past) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withValues(alpha: 0.95),
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.8,
            child: Column(
              children: [
                ListTile(
                  autofocus: true,
                  leading: const Icon(
                    Icons.live_tv,
                    color: Colors.red,
                  ),
                  title: const Text(
                    "Live",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _playLive();
                  },
                ),
                const Divider(height: 1, color: Colors.white24),
                Expanded(
                  child: ListView.builder(
                    itemCount: past.length,
                    itemBuilder: (_, i) {
                      final p = past[i];
                      final local = p.start.toLocal();
                      return ListTile(
                        dense: true,
                        leading: Text(
                          _stamp(local),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        title: Text(
                          p.title.isEmpty ? "—" : p.title,
                          style: const TextStyle(color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _playArchive(p);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _stamp(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return "${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}";
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ---------------------------------------------------------------------------

  Future<void> _toggleFavorite() async {
    final value = !_isFav;
    await Sql.favoriteChannel(widget.channel.id!, value);
    widget.channel.favorite = value;
    if (mounted) setState(() => _isFav = value);
  }

  List<_ControlAction> get _controls => [
    _ControlAction(Icons.replay_30, () => _seekRelative(-30)),
    _ControlAction(Icons.replay_5, () => _seekRelative(-5)),
    _ControlAction(_isPlaying ? Icons.pause : Icons.play_arrow, _togglePlay),
    _ControlAction(Icons.forward_5, () => _seekRelative(5)),
    _ControlAction(Icons.forward_30, () => _seekRelative(30)),
    _ControlAction(
      _isFav ? Icons.favorite : Icons.favorite_border,
      _toggleFavorite,
    ),
    _ControlAction(Icons.audiotrack, _openAudioModal),
    if (_isLive) _ControlAction(Icons.history, _openArchiveMenu),
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
                        _archiveMode
                            ? "${widget.channel.name}  •  Archive"
                            : widget.channel.name,
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
    if (_archiveMode) {
      final p = _currentProgram;
      final label = p == null
          ? "ARCHIVE"
          : "ARCHIVE · ${_stamp(p.start.toLocal())}"
                "${p.title.isEmpty ? '' : '  ${p.title}'}";
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.history, color: Colors.amber, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    if (!_isMovie) {
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
    _watchdog?.cancel();
    _focusNode.dispose();
    _controller?.dispose(forceDispose: true);
    super.dispose();
  }
}
