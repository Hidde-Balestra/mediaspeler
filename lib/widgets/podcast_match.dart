import 'package:flutter/material.dart';

import '../services/podcast_directory.dart';
import 'common.dart';

/// Toont een gevonden podcastversie van een YouTube-kanaal.
class PodcastMatchCard extends StatelessWidget {
  final PodcastMatch match;
  const PodcastMatchCard({super.key, required this.match});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.podcasts, size: 18, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 6),
                Text('Podcastversie gevonden',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Cover(url: match.imageUrl, size: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(match.title,
                          style: theme.textTheme.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      Text(match.author,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Echte audio-afleveringen: werkt altijd, ook op de achtergrond, '
              'zonder blokkades van YouTube. Controleer even of dit dezelfde show is.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}
