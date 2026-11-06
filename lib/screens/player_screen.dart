import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';

/// Volledige speler: videobeeld voor video's, grote cover voor audio.
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final item = state.current;
    if (item == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Er speelt niets.')));
    }
    final isVideo = item.kind == MediaKind.video;

    return Scaffold(
      appBar: AppBar(
        title: Text(item.subtitle ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (isVideo)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Video(controller: state.videoController),
                ),
              )
            else
              Center(
                child: Cover(
                  url: item.imageUrl,
                  size: MediaQuery.sizeOf(context).shortestSide.clamp(160, 360) - 32,
                ),
              ),
            const SizedBox(height: 20),
            Text(item.title,
                style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            const PlayerControls(),
          ],
        ),
      ),
    );
  }
}

/// Voortgangsbalk, afspeelknoppen en snelheid.
class PlayerControls extends StatelessWidget {
  const PlayerControls({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final player = state.player;

    return Column(
      children: [
        StreamBuilder<Duration>(
          stream: player.stream.position,
          initialData: player.state.position,
          builder: (context, snap) {
            final pos = snap.data ?? Duration.zero;
            final dur = player.state.duration;
            final max = dur.inMilliseconds.toDouble();
            return Column(
              children: [
                Slider(
                  value: max > 0 ? pos.inMilliseconds.clamp(0, max).toDouble() : 0,
                  max: max > 0 ? max : 1,
                  onChanged: max > 0
                      ? (v) => player.seek(Duration(milliseconds: v.round()))
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text(formatDuration(pos)), Text(formatDuration(dur))],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 36,
              tooltip: '10 s terug',
              onPressed: () => state.skip(const Duration(seconds: -10)),
              icon: const Icon(Icons.replay_10),
            ),
            const SizedBox(width: 12),
            StreamBuilder<bool>(
              stream: player.stream.playing,
              initialData: player.state.playing,
              builder: (context, snap) => IconButton.filled(
                iconSize: 48,
                tooltip: snap.data == true ? 'Pauze' : 'Afspelen',
                onPressed: player.playOrPause,
                icon: Icon(snap.data == true ? Icons.pause : Icons.play_arrow),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              iconSize: 36,
              tooltip: '30 s vooruit',
              onPressed: () => state.skip(const Duration(seconds: 30)),
              icon: const Icon(Icons.forward_30),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          children: [
            for (final r in const [0.75, 1.0, 1.25, 1.5, 2.0])
              ChoiceChip(
                label: Text('${r}x'),
                selected: state.rate == r,
                onSelected: (_) => state.setRate(r),
              ),
          ],
        ),
      ],
    );
  }
}
