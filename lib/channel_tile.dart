import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:marquee/marquee.dart';
import 'package:open_tv/backend/epg.dart';
import 'package:open_tv/l10n/strings.dart';
import 'package:open_tv/backend/settings_service.dart';
import 'package:open_tv/backend/sql.dart';
import 'package:open_tv/backend/xtream.dart';
import 'package:open_tv/memory.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/error.dart';
import 'package:open_tv/models/media_type.dart';
import 'package:open_tv/models/node.dart';
import 'package:open_tv/models/node_type.dart';
import 'package:open_tv/player.dart';

class ChannelTile extends StatefulWidget {
  final Channel channel;
  final BuildContext parentContext;
  final Function(Node node) setNode;
  final VoidCallback? onFocusNavbar;
  final bool autofocus;
  const ChannelTile({
    super.key,
    required this.channel,
    required this.setNode,
    required this.parentContext,
    this.onFocusNavbar,
    this.autofocus = false,
  });

  @override
  State<ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<ChannelTile> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Only intercept Right (to reach the navbar). OK/Enter use the InkWell's
    // default activation (fires on press) so a residual key-up after navigation
    // can't accidentally trigger playback on a freshly focused tile.
    _focusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (!FocusScope.of(
          context,
        ).focusInDirection(TraversalDirection.right)) {
          widget.onFocusNavbar?.call();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    _focusNode.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> favorite() async {
    if (widget.channel.mediaType == MediaType.group) return;
    await Error.tryAsyncNoLoading(() async {
      final newValue = !widget.channel.favorite;
      await Sql.favoriteChannel(widget.channel.id!, newValue);
      setState(() {
        widget.channel.favorite = newValue;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newValue ? S.of(context).addedToFavorites : S.of(context).removedFromFavorites,
          ),
          duration: const Duration(milliseconds: 500),
        ),
      );
    }, context);
  }

  Future<void> showContextMenu() async {
    if (widget.channel.mediaType == MediaType.group) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.channel.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              ListTile(
                autofocus: true,
                leading: const Icon(Icons.play_arrow, color: Colors.white),
                title: Text(
                  S.of(ctx).play,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  play();
                },
              ),
              ListTile(
                leading: Icon(
                  widget.channel.favorite ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                ),
                title: Text(
                  widget.channel.favorite
                      ? S.of(ctx).removeFromFavorites
                      : S.of(ctx).addToFavorites,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  favorite();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> play() async {
    if (widget.channel.mediaType == MediaType.group ||
        widget.channel.mediaType == MediaType.serie) {
      if (widget.channel.mediaType == MediaType.serie &&
          !refreshedSeries.contains(widget.channel.id)) {
        await Error.tryAsync(
          () async {
            await getEpisodes(widget.channel);
            refreshedSeries.add(widget.channel.id!);
          },
          widget.parentContext,
          null,
          true,
          false,
        );
      }
      widget.setNode(
        Node(
          id: widget.channel.mediaType == MediaType.group
              ? widget.channel.id!
              : int.parse(widget.channel.url!),
          name: widget.channel.name,
          type: fromMediaType(widget.channel.mediaType),
        ),
      );
    } else {
      var settings = await SettingsService.getSettings();
      Sql.addToHistory(widget.channel.id!);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Player(channel: widget.channel, settings: settings),
        ),
      );
    }
  }

  // Scrolling "now playing" line under the channel name (livestreams only).
  Widget _nowPlayingLine() {
    if (widget.channel.mediaType != MediaType.livestream) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: nowPlaying,
      builder: (_, map, __) {
        final title = epgNowTitleFor(map, widget.channel.name);
        if (title == null || title.isEmpty) return const SizedBox.shrink();
        const style = TextStyle(
          color: Colors.white70,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        );
        return Padding(
          padding: const EdgeInsets.only(top: 3),
          child: SizedBox(
            height: 22,
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final tp = TextPainter(
                  text: TextSpan(text: title, style: style),
                  maxLines: 1,
                  textDirection: TextDirection.ltr,
                )..layout();
                final overflows = tp.width > constraints.maxWidth;
                tp.dispose();
                // Scroll only when the text doesn't fit AND the tile is focused
                // (keeps the list light on weak boxes).
                if (overflows && _focusNode.hasFocus) {
                  return Marquee(
                    text: title,
                    style: style,
                    velocity: 30,
                    blankSpace: 60,
                    startPadding: 0,
                    pauseAfterRound: const Duration(milliseconds: 1500),
                    accelerationDuration: const Duration(milliseconds: 300),
                    decelerationDuration: const Duration(milliseconds: 300),
                  );
                }
                return Text(
                  title,
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    return Card(
      elevation: focused ? 8.0 : 2.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        // Clear, high-contrast focus outline.
        side: focused
            ? const BorderSide(color: Color(0xFF4FC3F7), width: 3)
            : BorderSide.none,
      ),
      color: focused
          ? const Color(0xFF14323F)
          : Theme.of(context).colorScheme.surfaceContainer,
      child: InkWell(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onLongPress: showContextMenu,
        onTap: () async => await play(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                padding: const EdgeInsets.all(8.0),
                child: Center(
                  child: widget.channel.image != null
                      ? CachedNetworkImage(
                          imageUrl: widget.channel.image!,
                          // Logos render at ~84px in the grid; decoding at 160
                          // (instead of 300) cuts image memory ~3.5x per logo.
                          memCacheHeight: 160,
                          memCacheWidth: 160,
                          fit: BoxFit.contain,
                          errorWidget: (_, __, ___) => const Icon(
                            Icons.tv,
                            size: 45,
                            color: Colors.grey,
                          ),
                        )
                      : const Icon(Icons.tv, size: 45, color: Colors.grey),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.channel.name,
                      textAlign: TextAlign.left,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: Theme.of(
                          context,
                        ).textTheme.titleMedium?.fontSize!,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    _nowPlayingLine(),
                  ],
                ),
              ),
            ),
            if (widget.channel.favorite)
              Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: Center(
                  child: const Icon(Icons.star, size: 25, color: Colors.amber),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
