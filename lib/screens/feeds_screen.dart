import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../services/podcast_directory.dart';
import '../services/youtube_service.dart';
import '../widgets/podcast_match.dart';
import '../widgets/common.dart';
import 'feed_detail_screen.dart';

class FeedsScreen extends StatelessWidget {
  const FeedsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feeds'),
        actions: const [ThemeMenuButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Feed toevoegen'),
      ),
      body: state.feeds.isEmpty
          ? const _EmptyFeeds()
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: state.feeds.length,
              itemBuilder: (context, i) {
                final feed = state.feeds[i];
                return ListTile(
                  leading: Cover(url: feed.imageUrl),
                  title: Text(feed.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      [
                        if (feed.isYouTube)
                          feed.audioOnly ? 'YouTube · alleen audio' : 'YouTube',
                        feed.description ?? (feed.isYouTube ? '' : feed.url),
                      ].where((s) => s.isNotEmpty).join('\n'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => FeedDetailScreen(feed: feed))),
                  trailing: IconButton(
                    tooltip: 'Verwijderen',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmRemove(context, feed),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, Feed feed) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Feed verwijderen?'),
        content: Text(feed.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuleren')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Verwijderen')),
        ],
      ),
    );
    if (ok == true && context.mounted) await AppScope.read(context).removeFeed(feed);
  }

  Future<void> _showAddDialog(BuildContext context) async {
    await showDialog(context: context, builder: (_) => const _AddFeedDialog());
  }
}

class _EmptyFeeds extends StatelessWidget {
  const _EmptyFeeds();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.podcasts, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('Nog geen feeds', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Voeg een podcastfeed of YouTube-kanaal toe met de knop hieronder.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddFeedDialog extends StatefulWidget {
  const _AddFeedDialog();

  @override
  State<_AddFeedDialog> createState() => _AddFeedDialogState();
}

class _AddFeedDialogState extends State<_AddFeedDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  bool _audioOnly = true;
  String? _error;

  /// Gevonden podcastversie van het YouTube-kanaal (stap 1 van "als podcast").
  PodcastMatch? _match;

  bool get _isYouTube => YouTubeService.looksLikeYouTube(_controller.text);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() => _match = null));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(AppState state) action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(AppScope.read(context));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_controller.text.trim().isEmpty) return;
    final input = _controller.text;
    await _run((state) async {
      // Als podcast: eerst kijken of het kanaal een echte podcastfeed heeft.
      if (_isYouTube && _audioOnly) {
        final match = await state.findPodcastVersion(input);
        if (match != null) {
          if (mounted) setState(() => _match = match);
          return;
        }
      }
      await state.addFeed(input, audioOnly: _isYouTube && _audioOnly);
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _addPodcast() => _run((state) async {
        await state.addFeed(_match!.feedUrl);
        if (mounted) Navigator.of(context).pop();
      });

  Future<void> _addYouTubeAnyway() => _run((state) async {
        await state.addFeed(_controller.text, audioOnly: true);
        if (mounted) Navigator.of(context).pop();
      });

  @override
  Widget build(BuildContext context) {
    final match = _match;
    return AlertDialog(
      title: const Text('Feed toevoegen'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'RSS-adres of YouTube-kanaal',
                hintText: 'https://… of @kanaalnaam',
                helperText: 'Podcastfeed, YouTube-kanaal (youtube.com/@naam) of playlist',
                helperMaxLines: 2,
                errorText: _error,
                errorMaxLines: 3,
                prefixIcon: Icon(_isYouTube ? Icons.smart_display : Icons.rss_feed),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_isYouTube && match == null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _audioOnly,
                onChanged: _busy ? null : (v) => setState(() => _audioOnly = v),
                title: const Text('Afspelen als podcast'),
                subtitle: const Text('Alleen audio, zonder beeld. Bespaart veel data.'),
              ),
            if (match != null) ...[
              const SizedBox(height: 16),
              PodcastMatchCard(match: match),
            ],
          ],
        ),
      ),
      actions: match != null
          ? [
              TextButton(
                  onPressed: _busy ? null : _addYouTubeAnyway,
                  child: const Text('Toch via YouTube')),
              FilledButton(
                onPressed: _busy ? null : _addPodcast,
                child: _busy ? const _Spinner() : const Text('Als podcast toevoegen'),
              ),
            ]
          : [
              TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('Annuleren')),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy ? const _Spinner() : const Text('Toevoegen'),
              ),
            ],
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
}
