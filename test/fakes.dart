import 'package:mediaspeler/services/podcast_directory.dart';
import 'package:mediaspeler/services/youtube_service.dart';

/// Nep-YouTube: geen netwerk, wel bijhouden wat er gevraagd wordt.
class FakeYouTube extends YouTubeService {
  final List<String> resolved = [];
  final List<(String, bool)> streams = [];
  Object? streamError;
  Object? resolveError;

  @override
  Future<YouTubeFeedRef> resolveFeed(String input) async {
    resolved.add(input);
    if (resolveError != null) throw resolveError!;
    return const YouTubeFeedRef(
        'https://www.youtube.com/feeds/videos.xml?channel_id=UCtest',
        title: 'Kanaal',
        imageUrl: 'https://yt3.example/logo.jpg');
  }

  @override
  Future<Uri> streamUrl(String videoId, {required bool audioOnly}) async {
    streams.add((videoId, audioOnly));
    if (streamError != null) throw streamError!;
    return Uri.parse('https://stream.example/$videoId');
  }
}

/// Nep-podcastgids: geeft een vaste match terug (of niets).
class FakePodcasts extends PodcastDirectory {
  PodcastMatch? match;
  final List<String> searched = [];
  FakePodcasts([this.match]);

  @override
  Future<PodcastMatch?> findFor(String channelTitle, {String? handle}) async {
    searched.add(channelTitle);
    return match;
  }
}
