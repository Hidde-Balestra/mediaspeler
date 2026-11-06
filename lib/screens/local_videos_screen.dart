import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'player_screen.dart';

class LocalVideosScreen extends StatelessWidget {
  const LocalVideosScreen({super.key});

  Future<void> _pick(BuildContext context) async {
    final state = AppScope.read(context);
    final files = await FilePicker.pickFiles(
      dialogTitle: "Kies video's",
      type: FileType.video,
    );
    if (files.isEmpty) return;
    await state.addLocalVideos([
      for (final f in files)
        LocalVideo(
          // Bestandspad waar mogelijk, anders de content:// URI (Android).
          uri: f.path ?? f.uri.toString(),
          name: f.name,
          added: DateTime.now(),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final videos = state.localVideos;
    return Scaffold(
      appBar: AppBar(title: const Text('Op dit apparaat')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _pick(context),
        icon: const Icon(Icons.video_file),
        label: const Text("Video's kiezen"),
      ),
      body: videos.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.video_library,
                        size: 72, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text("Nog geen video's", style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text(
                      "Kies video's van je apparaat om ze hier af te spelen.",
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: videos.length,
              itemBuilder: (context, i) {
                final v = videos[i];
                final item = MediaItem.fromLocal(v);
                final saved = state.savedPosition(item.id);
                return Dismissible(
                  key: ValueKey(v.uri),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: const Icon(Icons.delete),
                  ),
                  onDismissed: (_) => state.removeLocalVideo(v),
                  child: ListTile(
                    leading: const Cover(fallbackIcon: Icons.movie),
                    title: Text(v.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(saved != null
                        ? 'Verder vanaf ${formatDuration(saved)}'
                        : 'Toegevoegd ${formatDate(v.added)}'),
                    onTap: () async {
                      await state.play(item);
                      if (context.mounted) {
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const PlayerScreen()));
                      }
                    },
                  ),
                );
              },
            ),
    );
  }
}
