import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../services/podcast_directory.dart';
import '../services/source_resolver.dart';
import '../services/youtube_service.dart';
import '../widgets/common.dart';
import '../widgets/episode_tile.dart';
import '../widgets/podcast_match.dart';
import 'feed_detail_screen.dart';

/// Wat er na het dialoogvenster moet gebeuren (door het scherm eronder).
class AddOutcome {
  final Feed? feed;
  final MediaItem? play;
  final String? message;
  const AddOutcome({this.feed, this.play, this.message});
}

/// Toont het venster "Toevoegen of zoeken" en handelt het resultaat af:
/// feed openen, aflevering of bestand afspelen, melding tonen.
Future<void> showAddSourceDialog(BuildContext context) async {
  final outcome = await showDialog<AddOutcome>(
      context: context, builder: (_) => const AddSourceDialog());
  if (outcome == null || !context.mounted) return;
  if (outcome.message != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(outcome.message!)));
  }
  if (outcome.play != null) {
    await playMediaItem(context, outcome.play!);
  } else if (outcome.feed != null) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => FeedDetailScreen(feed: outcome.feed!)));
  }
}

class AddSourceDialog extends StatefulWidget {
  const AddSourceDialog({super.key});

  @override
  State<AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<AddSourceDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  bool _audioOnly = true;
  String? _error;

  /// Tussenstappen: gevonden podcastversie (YouTube), keuzelijst, afspeelbaar bestand,
  /// of een melding met een link om elders te openen.
  PodcastMatch? _ytMatch;
  PodcastChoice? _choice;
  PlayableSource? _playable;
  Unsupported? _unsupported;

  bool get _isYouTube => YouTubeService.looksLikeYouTube(_controller.text);
  bool get _isUrl => SourceResolver.looksLikeUrl(_controller.text);
  bool get _hasStep =>
      _ytMatch != null || _choice != null || _playable != null || _unsupported != null;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {
          _ytMatch = null;
          _choice = null;
          _playable = null;
          _unsupported = null;
        }));
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

  void _done(AddOutcome outcome) {
    if (mounted) Navigator.of(context).pop(outcome);
  }

  Future<void> _submit() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;
    await _run((state) async {
      final res = await state.sources.resolve(input);
      if (!mounted) return;
      switch (res) {
        case YouTubeSource():
          // Als podcast: eerst kijken of het kanaal een echte podcastfeed heeft.
          if (_audioOnly) {
            final match = await state.findPodcastVersion(input);
            if (match != null) {
              setState(() => _ytMatch = match);
              return;
            }
          }
          final feed = await state.addFeed(input, audioOnly: _audioOnly);
          _done(AddOutcome(feed: feed));
        case FeedSource(:final feedUrl, :final via, :final episodeTitle):
          await _addFeedAndMaybePlay(state, feedUrl, via: via, episodeTitle: episodeTitle);
        case PodcastChoice():
          setState(() => _choice = res);
        case PlayableSource():
          setState(() => _playable = res);
        case Unsupported():
          setState(() => _unsupported = res);
      }
    });
  }

  /// Voegt een feed toe (of gebruikt hem als je hem al volgt) en speelt, als de
  /// link naar één aflevering wees, die aflevering meteen af.
  Future<void> _addFeedAndMaybePlay(AppState state, String feedUrl,
      {String? via, String? episodeTitle}) async {
    var feed = state.feedByUrl(feedUrl);
    final already = feed != null;
    feed ??= await state.addFeed(feedUrl);
    if (episodeTitle != null) {
      final ep = state.findEpisode(feed.url, episodeTitle);
      if (ep != null) {
        return _done(AddOutcome(
          play: MediaItem.fromEpisode(ep, feedTitle: feed.title),
          message: already ? null : '"${feed.title}" toegevoegd${via != null ? ' (via $via)' : ''}.',
        ));
      }
    }
    _done(AddOutcome(
      feed: feed,
      message: already
          ? 'Je volgt "${feed.title}" al.'
          : via != null
              ? 'Gevonden via $via: "${feed.title}" toegevoegd.'
              : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final choice = _choice;
    final playable = _playable;
    final unsupported = _unsupported;
    final ytMatch = _ytMatch;

    return AlertDialog(
      title: const Text('Toevoegen of zoeken'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                decoration: InputDecoration(
                  labelText: 'Link of naam',
                  hintText: 'Podcastnaam, RSS, YouTube, Spotify…',
                  helperText: 'Werkt met RSS-feeds, YouTube, Spotify, Apple Podcasts, '
                      'websites en losse audio-/videolinks. Of typ een naam om te zoeken.',
                  helperMaxLines: 3,
                  errorText: _error,
                  errorMaxLines: 4,
                  prefixIcon: Icon(_sourceIcon()),
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_isYouTube && !_hasStep)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _audioOnly,
                  onChanged: _busy ? null : (v) => setState(() => _audioOnly = v),
                  title: const Text('Afspelen als podcast'),
                  subtitle: const Text('Alleen audio, zonder beeld. Bespaart veel data.'),
                ),
              if (ytMatch != null) ...[
                const SizedBox(height: 16),
                PodcastMatchCard(match: ytMatch),
              ],
              if (choice != null) ...[
                const SizedBox(height: 12),
                Text(
                  choice.via == 'Spotify'
                      ? 'Spotify-podcasts kunnen alleen in de Spotify-app spelen, maar deze '
                          'podcast is ook als gewone feed te volgen. Kies de juiste:'
                      : 'Kies een podcast:',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                for (final m in choice.options)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Cover(url: m.imageUrl, size: 48),
                    title: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(m.author, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.add_circle_outline),
                    enabled: !_busy,
                    onTap: () => _run((state) => _addFeedAndMaybePlay(state, m.feedUrl,
                        via: choice.via == 'Zoekresultaten' ? null : choice.via,
                        episodeTitle: choice.episodeTitle)),
                  ),
              ],
              if (playable != null) ...[
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(
                        playable.kind == MediaKind.video ? Icons.movie : Icons.audiotrack),
                    title: Text(playable.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(playable.kind == MediaKind.video
                        ? 'Videobestand: kan direct in deze app afspelen'
                        : 'Audiobestand: kan direct in deze app afspelen'),
                  ),
                ),
              ],
              if (unsupported != null) ...[
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(unsupported.message,
                        style:
                            TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: _actions(),
    );
  }

  IconData _sourceIcon() {
    final s = _controller.text.toLowerCase();
    if (_isYouTube) return Icons.smart_display;
    if (s.contains('spotify')) return Icons.graphic_eq;
    if (s.contains('apple.com') || s.contains('overcast')) return Icons.podcasts;
    if (s.isNotEmpty && !_isUrl) return Icons.search;
    return Icons.rss_feed;
  }

  List<Widget> _actions() {
    final cancel = TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Annuleren'));
    final openUrl = _choice?.openUrl ?? _unsupported?.openUrl;
    final openLabel = _choice?.openLabel ?? _unsupported?.openLabel ?? 'Openen';
    final open = openUrl == null
        ? null
        : TextButton.icon(
            onPressed: () => launchUrl(openUrl, mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(openLabel),
          );

    if (_ytMatch != null) {
      return [
        TextButton(
            onPressed: _busy
                ? null
                : () => _run((state) async {
                      final feed = await state.addFeed(_controller.text, audioOnly: true);
                      _done(AddOutcome(feed: feed));
                    }),
            child: const Text('Toch via YouTube')),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run((state) => _addFeedAndMaybePlay(state, _ytMatch!.feedUrl)),
          child: _busy ? const _Spinner() : const Text('Als podcast toevoegen'),
        ),
      ];
    }
    if (_playable != null) {
      final p = _playable!;
      return [
        cancel,
        FilledButton.icon(
          onPressed: () => _done(AddOutcome(
              play: MediaItem(id: 'url:${p.url}', title: p.title, uri: p.url, kind: p.kind))),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Nu afspelen'),
        ),
      ];
    }
    if (_choice != null || _unsupported != null) {
      return [?open, cancel];
    }
    return [
      cancel,
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: _busy
            ? const _Spinner()
            : Text(_controller.text.isNotEmpty && !_isUrl ? 'Zoeken' : 'Toevoegen'),
      ),
    ];
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
}
