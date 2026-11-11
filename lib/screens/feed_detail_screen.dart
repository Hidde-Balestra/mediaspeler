import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../services/podcast_directory.dart';
import '../widgets/podcast_match.dart';
import '../widgets/episode_tile.dart';
import '../widgets/common.dart';

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
      final state = AppScope.read(context);
      final last = state.feedByUrl(widget.feed.url)?.lastFetched;
      // Bewaarde afleveringen meteen tonen; ouder dan een half uur: op de achtergrond vernieuwen.
      if (state.episodesFor(widget.feed.url) == null ||
          last == null ||
          DateTime.now().difference(last) > const Duration(minutes: 30)) {
        _refresh();
      }
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

  Future<void> _findPodcast(Feed feed) async {
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Zoeken naar een podcastversie…')));
    final PodcastMatch? match;
    try {
      match = await state.findPodcastVersionFor(feed);
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Zoeken mislukt; controleer je verbinding.')));
      return;
    }
    messenger.hideCurrentSnackBar();
    if (!mounted) return;
    if (match == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Geen podcastversie van dit kanaal gevonden (of je volgt hem al).')));
      return;
    }
    final found = match;
    var replace = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: const Text('Als podcast volgen?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PodcastMatchCard(match: found),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: replace,
                onChanged: (v) => setDialog(() => replace = v ?? true),
                title: const Text('YouTube-kanaal daarna verwijderen'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuleren')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true), child: const Text('Podcast toevoegen')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final added = await state.addFeed(found.feedUrl);
      if (replace) await state.removeFeed(feed);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => FeedDetailScreen(feed: added)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Toevoegen mislukt: $e')));
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
            return EpisodeTile(episode: episodes[i - 1], feed: feed);
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
              tooltip: 'Podcastversie zoeken',
              icon: const Icon(Icons.podcasts),
              onPressed: () => _findPodcast(feed),
            ),
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
