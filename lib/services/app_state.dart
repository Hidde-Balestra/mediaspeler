import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models.dart';
import 'rss_service.dart';
import 'storage.dart';
import 'youtube_service.dart';

/// Centrale app-status: abonnementen, lokale video's en de speler.
class AppState extends ChangeNotifier {
  final Storage storage;
  final RssService rss;
  final YouTubeService youtube;

  AppState(this.storage, {RssService? rss, YouTubeService? youtube})
      : rss = rss ?? RssService(),
        youtube = youtube ?? YouTubeService() {
    feeds = storage.loadFeeds();
    localVideos = storage.loadLocalVideos();
    finished = storage.finished();
    themeMode = parseThemeMode(storage.themeMode());
  }

  // ---------------- Thema ----------------

  late ThemeMode themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await storage.setThemeMode(mode.name);
  }

  static ThemeMode parseThemeMode(String? s) =>
      ThemeMode.values.firstWhere((m) => m.name == s, orElse: () => ThemeMode.system);

  // ---------------- Feeds ----------------

  late List<Feed> feeds;
  final Map<String, List<Episode>> _episodes = {};
  final Set<String> _loading = {};
  late Set<String> finished;

  List<Episode>? episodesFor(String feedUrl) => _episodes[feedUrl];
  bool isLoading(String feedUrl) => _loading.contains(feedUrl);

  /// Voegt een feed toe na hem eerst op te halen (zodat een fout direct zichtbaar is).
  /// Een YouTube-kanaal, `@handle` of playlist wordt omgezet naar de RSS-feed van YouTube.
  /// Met [audioOnly] worden video's uit deze feed als podcast (alleen audio) afgespeeld.
  Future<Feed> addFeed(String url, {bool audioOnly = false}) async {
    var normalized = url.trim();
    String? fallbackImage;
    String? fallbackTitle;
    if (YouTubeService.looksLikeYouTube(normalized)) {
      final ref = await youtube.resolveFeed(normalized);
      normalized = ref.feedUrl;
      fallbackImage = ref.imageUrl;
      fallbackTitle = ref.title;
    } else if (!normalized.startsWith(RegExp(r'https?://'))) {
      normalized = 'https://$normalized';
    }
    if (feeds.any((f) => f.url == normalized)) {
      throw Exception('Deze feed staat al in je lijst');
    }
    final result = await rss.fetch(normalized);
    final feed = Feed(
      url: normalized,
      title: result.feed.title == normalized && fallbackTitle != null
          ? fallbackTitle
          : result.feed.title,
      description: result.feed.description,
      // YouTube-feeds hebben geen afbeelding: gebruik het kanaallogo of de eerste thumbnail.
      imageUrl: result.feed.imageUrl ??
          fallbackImage ??
          (result.episodes.isNotEmpty ? result.episodes.first.imageUrl : null),
      lastFetched: result.feed.lastFetched,
      audioOnly: audioOnly,
    );
    feeds = [...feeds, feed];
    _episodes[normalized] = result.episodes;
    await storage.saveFeeds(feeds);
    notifyListeners();
    return feed;
  }

  /// Video's uit deze feed als podcast afspelen (alleen audio) of met beeld.
  Future<void> setAudioOnly(Feed feed, bool audioOnly) async {
    feeds = [
      for (final f in feeds) f.url == feed.url ? f.copyWith(audioOnly: audioOnly) : f
    ];
    await storage.saveFeeds(feeds);
    notifyListeners();
  }

  Feed? feedByUrl(String url) {
    for (final f in feeds) {
      if (f.url == url) return f;
    }
    return null;
  }

  Future<void> removeFeed(Feed feed) async {
    feeds = feeds.where((f) => f.url != feed.url).toList();
    _episodes.remove(feed.url);
    await storage.saveFeeds(feeds);
    notifyListeners();
  }

  Future<void> refreshFeed(Feed feed) async {
    _loading.add(feed.url);
    notifyListeners();
    try {
      final result = await rss.fetch(feed.url);
      _episodes[feed.url] = result.episodes;
      feeds = [
        for (final f in feeds)
          f.url == feed.url
              ? f.copyWith(
                  title: result.feed.title,
                  description: result.feed.description,
                  imageUrl: result.feed.imageUrl,
                  lastFetched: DateTime.now())
              : f
      ];
      await storage.saveFeeds(feeds);
    } finally {
      _loading.remove(feed.url);
      notifyListeners();
    }
  }

  Future<void> toggleFinished(String id) async {
    final done = !finished.contains(id);
    await storage.setFinished(id, done);
    finished = storage.finished();
    if (done) await storage.clearPosition(id);
    notifyListeners();
  }

  // ---------------- Lokale video's ----------------

  late List<LocalVideo> localVideos;

  Future<void> addLocalVideos(List<LocalVideo> videos) async {
    final existing = localVideos.map((v) => v.uri).toSet();
    localVideos = [...localVideos, ...videos.where((v) => !existing.contains(v.uri))];
    await storage.saveLocalVideos(localVideos);
    notifyListeners();
  }

  Future<void> removeLocalVideo(LocalVideo video) async {
    localVideos = localVideos.where((v) => v.uri != video.uri).toList();
    await storage.saveLocalVideos(localVideos);
    await storage.clearPosition(MediaItem.fromLocal(video).id);
    notifyListeners();
  }

  // ---------------- Speler ----------------

  // De speler wordt pas aangemaakt bij eerste gebruik, zodat de rest van de
  // app-status ook zonder native media-bibliotheken werkt (bijv. in tests).
  Player? _player;
  Player get player => _player ??= _createPlayer();
  late final VideoController videoController = VideoController(player);
  MediaItem? current;
  double rate = 1.0;

  final List<StreamSubscription> _subs = [];
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  Player _createPlayer() {
    final player = Player();
    _subs.add(player.stream.position.listen((pos) {
      final item = current;
      if (item == null) return;
      // Elke 5 seconden de positie bewaren.
      if (DateTime.now().difference(_lastSave) > const Duration(seconds: 5)) {
        _lastSave = DateTime.now();
        storage.savePosition(item.id, pos);
      }
    }));
    _subs.add(player.stream.completed.listen((done) async {
      final item = current;
      if (!done || item == null) return;
      await storage.clearPosition(item.id);
      if (!finished.contains(item.id)) {
        await storage.setFinished(item.id, true);
        finished = storage.finished();
        notifyListeners();
      }
    }));
    return player;
  }

  Duration? savedPosition(String id) => storage.position(id);

  Future<void> play(MediaItem item) async {
    // Zelfde item in dezelfde vorm: gewoon doorgaan. Wisselen tussen audio en
    // video van hetzelfde item opent hem opnieuw vanaf de huidige positie.
    if (current?.id == item.id && current?.kind == item.kind) {
      await player.play();
      return;
    }
    await _saveCurrentPosition();
    final previous = current;
    current = item;
    notifyListeners();
    final String uri;
    try {
      uri = item.youtubeId != null
          ? (await youtube.streamUrl(item.youtubeId!, audioOnly: item.kind == MediaKind.audio))
              .toString()
          : item.uri;
    } catch (_) {
      // Stream ophalen mislukt: het vorige item speelt nog gewoon door.
      if (identical(current, item)) {
        current = previous;
        notifyListeners();
      }
      rethrow;
    }
    final start = storage.position(item.id);
    await player.open(Media(uri, start: start));
    await player.setRate(rate);
  }

  Future<void> setRate(double value) async {
    rate = value;
    await player.setRate(value);
    notifyListeners();
  }

  Future<void> skip(Duration delta) async {
    final pos = player.state.position + delta;
    final dur = player.state.duration;
    await player.seek(pos < Duration.zero
        ? Duration.zero
        : (dur > Duration.zero && pos > dur ? dur : pos));
  }

  Future<void> stop() async {
    await _saveCurrentPosition();
    await _player?.stop();
    current = null;
    notifyListeners();
  }

  Future<void> _saveCurrentPosition() async {
    final item = current;
    final p = _player;
    if (item == null || p == null) return;
    final pos = p.state.position;
    if (pos > const Duration(seconds: 5)) await storage.savePosition(item.id, pos);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    youtube.close();
    super.dispose();
  }
}

/// Maakt [AppState] beschikbaar in de widget-boom.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
