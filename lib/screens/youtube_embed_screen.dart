import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models.dart';
import '../services/app_state.dart';

/// Of de officiële YouTube-speler in de app kan draaien (webview: Android en iOS).
bool get canEmbedYouTube => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Speelt een YouTube-video af als alleen-audio niet lukt: in de app met de
/// officiële YouTube-speler, of anders in de YouTube-app / browser.
Future<void> playViaYouTube(BuildContext context, MediaItem item, {String? reason}) async {
  final id = item.youtubeId!;
  final state = AppScope.read(context);
  // Niet twee dingen tegelijk laten spelen.
  if (state.current != null) await state.player.pause();
  await state.storage.setLastPlayed(item);
  if (!context.mounted) return;
  if (canEmbedYouTube) {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => YouTubeEmbedScreen(item: item, reason: reason)));
  } else {
    await launchUrl(Uri.parse('https://www.youtube.com/watch?v=$id'),
        mode: LaunchMode.externalApplication);
  }
}

class YouTubeEmbedScreen extends StatefulWidget {
  final MediaItem item;
  final String? reason;
  const YouTubeEmbedScreen({super.key, required this.item, this.reason});

  @override
  State<YouTubeEmbedScreen> createState() => _YouTubeEmbedScreenState();
}

class _YouTubeEmbedScreenState extends State<YouTubeEmbedScreen> {
  late final YoutubePlayerController _controller;
  late final AppState _state;
  Timer? _saveTimer;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _state = AppScope.read(context);
    final start = _state.savedPosition(widget.item.id);
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.item.youtubeId!,
      autoPlay: true,
      startSeconds: start?.inSeconds.toDouble(),
      params: const YoutubePlayerParams(
        showFullscreenButton: true,
        strictRelatedVideos: true,
        playsInline: true,
      ),
    );
    // Afspeelpositie bewaren, net als bij de gewone speler.
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _savePosition());
    // Scherm uit / app naar achtergrond: YouTube pauzeert dan; meteen de plek bewaren.
    _lifecycle = AppLifecycleListener(
      onInactive: _savePosition,
      onHide: _savePosition,
      onPause: _savePosition,
    );
  }

  Future<void> _savePosition() async {
    try {
      final t = await _controller.currentTime;
      final d = await _controller.duration;
      if (d > 0 && t >= d - 10) {
        await _state.storage.clearPosition(widget.item.id);
        if (!_state.finished.contains(widget.item.id)) await _state.toggleFinished(widget.item.id);
      } else if (t > 5) {
        await _state.storage.savePosition(
            widget.item.id, Duration(milliseconds: (t * 1000).round()));
      }
    } catch (_) {
      // Speler nog niet klaar of al gesloten.
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _lifecycle?.dispose();
    _savePosition().whenComplete(_controller.close);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.subtitle ?? 'YouTube',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Open in YouTube',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => launchUrl(
                Uri.parse('https://www.youtube.com/watch?v=${widget.item.youtubeId}'),
                mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            color: theme.colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.onTertiaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${widget.reason ?? 'Alleen de audio ophalen lukte niet.'} '
                      'Deze video speelt daarom via de officiële YouTube-speler: '
                      'met beeld (meer data) en alleen zolang dit scherm open is; '
                      'YouTube staat afspelen op het vergrendelscherm hier niet toe. '
                      'Je plek wordt onthouden.',
                      style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: YoutubePlayer(controller: _controller),
          ),
          const SizedBox(height: 16),
          Text(widget.item.title,
              style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
