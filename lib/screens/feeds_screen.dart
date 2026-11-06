import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'feed_detail_screen.dart';

class FeedsScreen extends StatelessWidget {
  const FeedsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Feeds')),
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
                  subtitle: Text(feed.description ?? feed.url,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
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
              'Voeg een RSS-feed van een podcast of videokanaal toe met de knop hieronder.',
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
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_controller.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).addFeed(_controller.text);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Feed toevoegen'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        enabled: !_busy,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: 'RSS-adres',
          hintText: 'https://voorbeeld.nl/podcast.xml',
          errorText: _error,
          errorMaxLines: 3,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Annuleren')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Toevoegen'),
        ),
      ],
    );
  }
}
