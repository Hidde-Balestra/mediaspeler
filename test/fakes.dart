import 'dart:async';

import 'package:mediaspeler/services/media_engine.dart';
import 'package:mediaspeler/services/podcast_directory.dart';
import 'package:mediaspeler/services/youtube_service.dart';

/// Nep-YouTube: geen netwerk, wel bijhouden wat er gevraagd wordt.
class FakeYouTube extends YouTubeService {
  final List<String> resolved = [];
  final List<(String, bool)> streams = [];
  Object? streamError;
  Object? resolveError;
  final List<String> invalidated = [];

  @override
  void invalidate(String videoId) => invalidated.add(videoId);

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

/// Gebeurtenisstromen van de nepspeler.
class FakeStreams implements EngineStreams {
  final positionC = StreamController<Duration>.broadcast(sync: true);
  final durationC = StreamController<Duration>.broadcast(sync: true);
  final playingC = StreamController<bool>.broadcast(sync: true);
  final bufferingC = StreamController<bool>.broadcast(sync: true);
  final completedC = StreamController<bool>.broadcast(sync: true);
  final rateC = StreamController<double>.broadcast(sync: true);
  final errorC = StreamController<String>.broadcast(sync: true);

  @override
  Stream<Duration> get position => positionC.stream;
  @override
  Stream<Duration> get duration => durationC.stream;
  @override
  Stream<bool> get playing => playingC.stream;
  @override
  Stream<bool> get buffering => bufferingC.stream;
  @override
  Stream<bool> get completed => completedC.stream;
  @override
  Stream<double> get rate => rateC.stream;
  @override
  Stream<String> get error => errorC.stream;
}

/// Nepspeler: houdt bij wat er gevraagd wordt en laat tests gebeurtenissen sturen
/// (positie, duur, einde, fout) alsof media_kit ze gaf.
class FakeEngine extends MediaEngine implements EngineState {
  @override
  final FakeStreams stream = FakeStreams();
  @override
  EngineState get state => this;

  final List<(String, Duration?)> opened = [];
  final List<Duration> seeks = [];
  int plays = 0, pauses = 0, stops = 0;
  bool disposed = false;

  /// Duur die na open() wordt gemeld (0 = geen duur, zoals bij een livestream).
  Duration durationOnOpen = const Duration(minutes: 60);

  /// Of de speler de startpositie van open() zelf toepast (bij sommige streams niet).
  bool honoursStart = true;

  @override
  Duration position = Duration.zero;
  @override
  Duration duration = Duration.zero;
  @override
  Duration buffer = Duration.zero;
  @override
  bool playing = false;
  @override
  bool buffering = false;
  @override
  bool completed = false;
  @override
  double rate = 1.0;

  @override
  Future<void> open(String uri, {Duration? start}) async {
    opened.add((uri, start));
    completed = false;
    duration = Duration.zero;
    setPosition(honoursStart && start != null ? start : Duration.zero);
    setPlaying(true);
    if (durationOnOpen > Duration.zero) {
      // Even later komt de duur binnen, zoals bij een echte stream.
      scheduleMicrotask(() => setDuration(durationOnOpen));
    }
  }

  @override
  Future<void> play() async {
    plays++;
    setPlaying(true);
  }

  @override
  Future<void> pause() async {
    pauses++;
    setPlaying(false);
  }

  @override
  Future<void> playOrPause() => playing ? pause() : play();

  @override
  Future<void> seek(Duration p) async {
    seeks.add(p);
    setPosition(p);
  }

  @override
  Future<void> setRate(double r) async {
    rate = r;
    stream.rateC.add(r);
  }

  @override
  Future<void> stop() async {
    stops++;
    setPlaying(false);
  }

  @override
  Future<void> dispose() async => disposed = true;

  // ---- Hulpjes voor tests ----
  void setPosition(Duration p) {
    position = p;
    stream.positionC.add(p);
  }

  void setDuration(Duration d) {
    duration = d;
    stream.durationC.add(d);
  }

  void setPlaying(bool p) {
    playing = p;
    stream.playingC.add(p);
  }

  void setBuffering(bool b) {
    buffering = b;
    stream.bufferingC.add(b);
  }

  void finish() {
    completed = true;
    stream.completedC.add(true);
  }

  void fail(String message) => stream.errorC.add(message);
}
