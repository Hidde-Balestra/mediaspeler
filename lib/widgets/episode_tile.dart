import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../screens/player_screen.dart';
import '../screens/youtube_embed_screen.dart';
import '../services/app_state.dart';
import '../services/youtube_service.dart';
import 'common.dart';

/// Eén aflevering in een lijst, met afspeelknop en details.
/// Met [showFeed] staat de naam van de podcast/het kanaal erbij (voor de lijst "Nieuw").
class EpisodeTile extends StatelessWidget {
  final Episode episode;
  final Feed feed;
  final bool showFeed;
  const EpisodeTile(
      {super.key, required this.episode, required this.feed, this.showFeed = false});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final isCurrent = state.current?.id == episode.id;
    final done = state.finished.contains(episode.id);
    final saved = state.savedPosition(episode.id);

    final meta = [
      if (showFeed) feed.title,
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
      subtitle: Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis),
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

  Future<void> _play(BuildContext context, {bool? audioOnly}) =>
      playMediaItem(context, _item(audioOnly: audioOnly));

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


/// Speelt [item] af en opent bij video de speler. Lukt alleen-audio van YouTube
/// niet, dan via de officiële YouTube-speler; andere fouten als melding.
Future<void> playMediaItem(BuildContext context, MediaItem item) async {
  final state = AppScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await state.play(item);
  } on YouTubeException catch (e) {
    if (context.mounted) await playViaYouTube(context, item, reason: '${e.message}.');
    return;
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Afspelen mislukt: $e'),
        duration: const Duration(seconds: 8),
        action: item.youtubeId == null
            ? null
            : SnackBarAction(
                label: 'Open in YouTube',
                onPressed: () =>
                    launchUrl(Uri.parse(item.uri), mode: LaunchMode.externalApplication),
              ),
      ));
    return;
  }
  if (item.kind == MediaKind.video && context.mounted) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }
}
