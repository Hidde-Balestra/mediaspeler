import 'package:flutter/material.dart';

import '../models.dart';
import '../screens/player_screen.dart';
import '../services/app_state.dart';
import 'common.dart';

/// Kleine speler onderin, zichtbaar zolang er iets geladen is.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final item = state.current;
    if (item == null) return const SizedBox.shrink();
    final player = state.player;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const PlayerScreen())),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<Duration>(
              stream: player.stream.position,
              builder: (context, snap) {
                final dur = player.state.duration.inMilliseconds;
                final pos = (snap.data ?? Duration.zero).inMilliseconds;
                return LinearProgressIndicator(
                  value: dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0,
                  minHeight: 2,
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Cover(
                    url: item.imageUrl,
                    size: 44,
                    fallbackIcon:
                        item.kind == MediaKind.video ? Icons.movie : Icons.podcasts,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (item.subtitle != null)
                          Text(item.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  StreamBuilder<bool>(
                    stream: player.stream.playing,
                    initialData: player.state.playing,
                    builder: (context, snap) => IconButton(
                      tooltip: snap.data == true ? 'Pauze' : 'Afspelen',
                      onPressed: player.playOrPause,
                      icon: Icon(snap.data == true ? Icons.pause : Icons.play_arrow),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Stoppen',
                    onPressed: state.stop,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
