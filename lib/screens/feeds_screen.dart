import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';
import 'add_source_dialog.dart';
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
        heroTag: 'fab-feeds',
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
    await showAddSourceDialog(context);
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

