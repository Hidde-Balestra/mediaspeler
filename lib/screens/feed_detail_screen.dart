import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'player_screen.dart';

class FeedDetailScreen extends StatefulWidget {
  final Feed feed;
  const FeedDetailScreen({super.key, required this.feed});

  @override
  State<FeedDetailScreen> createState() => _FeedDetailScreenState();
}

class _FeedDetailScreenState extends State<FeedDetailScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (AppScope.read(context).episodesFor(widget.feed.url) == null) _refresh();
    });
  }

  Future<void> _refresh() async {
    setState(() => _error = null);
    try {
      await AppScope.read(context).refreshFeed(widget.feed);
    } catch (e) {
      if (mounted) setState(() => _error = 'Kon feed niet laden: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final feed = state.feeds.firstWhere((f) => f.url == widget.feed.url,
        orElse: () => widget.feed);
    final episodes = state.episodesFor(feed.url);
    final loading = state.isLoading(feed.url);

    Widget body;
    if (episodes == null && (loading || _error == null)) {
      body = const Center(child: CircularProgressIndicator());
    } else if (episodes == null) {
      body = _ErrorView(message: _error!, onRetry: _refresh);
    } else if (episodes.isEmpty) {
      body = const Center(child: Text('Deze feed bevat geen afspeelbare afleveringen.'));
    } else {
      body = RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.separated(
          itemCount: episodes.length + 1,
          separatorBuilder: (_, i) => i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
          itemBuilder: (context, i) {
            if (i == 0) return _FeedHeader(feed: feed, error: _error);
            return _EpisodeTile(episode: episodes[i - 1], feed: feed);
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(feed.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (feed.isYouTube)
            IconButton(
              tooltip: feed.audioOnly
                  ? 'Alleen audio (tik voor video met beeld)'
                  : 'Video met beeld (tik voor alleen audio)',
              isSelected: feed.audioOnly,
              icon: const Icon(Icons.videocam_outlined),
              selectedIcon: const Icon(Icons.headphones),
              onPressed: () {
                state.setAudioOnly(feed, !feed.audioOnly);
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                    content: Text(!feed.audioOnly
                        ? 'Afspelen als podcast: alleen audio'
                        : 'Afspelen als video met beeld'),
                  ));
              },
            ),
          IconButton(
            tooltip: 'Vernieuwen',
            onPressed: loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: body,
    );
  }
}

class _FeedHeader extends StatelessWidget {
  final Feed feed;
  final String? error;
  const _FeedHeader({required this.feed, this.error});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Cover(url: feed.imageUrl, size: 96),
              const SizedBox(width: 16),
              Expanded(
                child: Text(feed.description ?? '',
                    maxLines: 6, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final Episode episode;
  final Feed feed;
  const _EpisodeTile({required this.episode, required this.feed});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final isCurrent = state.current?.id == episode.id;
    final done = state.finished.contains(episode.id);
    final saved = state.savedPosition(episode.id);

    final meta = [
      if (episode.published != null) formatDate(episode.published!),
      if (episode.duration != null) formatDuration(episode.duration!),
      if (saved != null && !done) 'verder vanaf ${formatDuration(saved)}',
      if (done) 'beluisterd',
    ].join(' · ');
    final kind = _item().kind;

    return ListTile(
      leading: Stack(
        children: [
          Cover(
            url: episode.imageUrl,
            fallbackIcon: kind == MediaKind.video ? Icons.movie : Icons.podcasts,
          ),
          Positioned(
            right: 2,
            bottom: 2,
            child: Icon(
                kind == MediaKind.video
                    ? Icons.videocam
                    : (episode.youtubeId != null ? Icons.headphones : null),
                size: 16,
                color: Colors.white,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 4)]),
          ),
        ],
      ),
      title: Text(
        episode.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isCurrent ? FontWeight.bold : null,
          color: done ? Theme.of(context).disabledColor : null,
        ),
      ),
      subtitle: Text(meta),
      onTap: () => _showDetails(context),
      trailing: IconButton(
        tooltip: 'Afspelen',
        icon: Icon(isCurrent ? Icons.equalizer : Icons.play_circle_fill, size: 32),
        onPressed: () => _play(context),
      ),
    );
  }

  /// Hoe deze aflevering afgespeeld wordt: YouTube-feeds met "alleen audio" als podcast.
  MediaItem _item({bool? audioOnly}) => MediaItem.fromEpisode(
        episode,
        feedTitle: feed.title,
        audioOnly: episode.youtubeId != null && (audioOnly ?? feed.audioOnly),
      );

  Future<void> _play(BuildContext context, {bool? audioOnly}) async {
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final item = _item(audioOnly: audioOnly);
    try {
      await state.play(item);
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Afspelen mislukt: $e'),
          duration: const Duration(seconds: 8),
          action: episode.youtubeId == null
              ? null
              : SnackBarAction(
                  label: 'Open in YouTube',
                  onPressed: () => launchUrl(Uri.parse(episode.mediaUrl),
                      mode: LaunchMode.externalApplication),
                ),
        ));
      return;
    }
    if (item.kind == MediaKind.video && context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
    }
  }

  void _showDetails(BuildContext context) {
    final state = AppScope.read(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (c, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(episode.title, style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (episode.youtubeId == null)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      _play(context);
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Afspelen'),
                  )
                else ...[
                  for (final audio in feed.audioOnly ? [true, false] : [false, true])
                    (audio == feed.audioOnly ? FilledButton.icon : OutlinedButton.icon)(
                      onPressed: () {
                        Navigator.pop(c);
                        _play(context, audioOnly: audio);
                      },
                      icon: Icon(audio ? Icons.headphones : Icons.smart_display),
                      label: Text(audio ? 'Luisteren (alleen audio)' : 'Video bekijken'),
                    ),
                  TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse(episode.mediaUrl),
                        mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open in YouTube'),
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: () {
                    state.toggleFinished(episode.id);
                    Navigator.pop(c);
                  },
                  icon: const Icon(Icons.check),
                  label: Text(state.finished.contains(episode.id)
                      ? 'Markeer als niet beluisterd'
                      : 'Markeer als beluisterd'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(episode.description ?? 'Geen beschrijving.'),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Opnieuw proberen')),
          ],
        ),
      ),
    );
  }
}
