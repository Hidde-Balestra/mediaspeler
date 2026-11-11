import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models.dart';
import 'rss_service.dart';
import 'storage.dart';
import 'podcast_directory.dart';
import 'source_resolver.dart';
import 'youtube_service.dart';

/// Centrale app-status: abonnementen, lokale video's en de speler.
class AppState extends ChangeNotifier {
  final Storage storage;
  final RssService rss;
  final YouTubeService youtube;
  final PodcastDirectory podcasts;
  late final SourceResolver sources =
      _sources ?? SourceResolver(client: rss.client, directory: podcasts);
  final SourceResolver? _sources;

  AppState(this.storage,
      {RssService? rss,
      YouTubeService? youtube,
      PodcastDirectory? podcasts,
      SourceResolver? sources})
      : rss = rss ?? RssService(),
        youtube = youtube ?? YouTubeService(),
        podcasts = podcasts ?? PodcastDirectory(),
        _sources = sources {
    feeds = storage.loadFeeds();
    for (final f in feeds) {
      final cached = storage.loadEpisodes(f.url);
      if (cached.isNotEmpty) _episodes[f.url] = cached;
    }
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
    await storage.saveEpisodes(normalized, result.episodes);
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

  /// Zoekt de gewone podcastversie van een YouTube-kanaal (link, `@handle` of
  /// kanaalnaam). Null als er geen goede match is of je hem al volgt.
  Future<PodcastMatch?> findPodcastVersion(String youtubeInput) async {
    try {
      final ref = await youtube.resolveFeed(youtubeInput);
      final title = ref.title ?? (await rss.fetch(ref.feedUrl)).feed.title;
      return _unlessSubscribed(await podcasts.findFor(title, handle: ref.handle));
    } catch (_) {
      return null; // Niet gevonden is geen fout: dan gewoon via YouTube.
    }
  }

  /// Zelfde, voor een YouTube-kanaal dat al in je lijst staat.
  Future<PodcastMatch?> findPodcastVersionFor(Feed feed) async =>
      _unlessSubscribed(await podcasts.findFor(feed.title));

  PodcastMatch? _unlessSubscribed(PodcastMatch? m) =>
      m == null || feeds.any((f) => f.url == m.feedUrl) ? null : m;

  /// Alle afleveringen van alle feeds, nieuwste eerst (zonder datum achteraan).
  List<(Episode, Feed)> allEpisodes({MediaKind? kind, bool hideFinished = false}) {
    final out = <(Episode, Feed)>[];
    for (final f in feeds) {
      for (final e in _episodes[f.url] ?? const <Episode>[]) {
        if (hideFinished && finished.contains(e.id)) continue;
        if (kind != null && effectiveKind(e, f) != kind) continue;
        out.add((e, f));
      }
    }
    out.sort((a, b) {
      final da = a.$1.published, db = b.$1.published;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return out;
  }

  /// Audio of video zoals hij afgespeeld wordt (YouTube "als podcast" telt als audio).
  static MediaKind effectiveKind(Episode e, Feed f) =>
      e.youtubeId != null && f.audioOnly ? MediaKind.audio : e.kind;

  bool refreshingAll = false;

  /// Vernieuwt alle feeds (een paar tegelijk). Geeft het aantal mislukte feeds terug.
  Future<int> refreshAll() async {
    if (refreshingAll) return 0;
    refreshingAll = true;
    notifyListeners();
    var failed = 0;
    try {
      final queue = [...feeds];
      Future<void> worker() async {
        while (queue.isNotEmpty) {
          final f = queue.removeLast();
          try {
            await refreshFeed(f);
          } catch (_) {
            failed++;
          }
        }
      }

      await Future.wait([for (var i = 0; i < 4; i++) worker()]);
    } finally {
      refreshingAll = false;
      notifyListeners();
    }
    return failed;
  }

  /// De aflevering uit [feedUrl] die het best bij [title] past (voor links naar één aflevering).
  Episode? findEpisode(String feedUrl, String title) {
    Episode? best;
    var bestScore = 0.0;
    for (final e in _episodes[feedUrl] ?? const <Episode>[]) {
      final s = e.title.trim().toLowerCase() == title.trim().toLowerCase()
          ? 1.0
          : PodcastDirectory.similarity(e.title, title);
      if (s > bestScore) {
        bestScore = s;
        best = e;
      }
    }
    return bestScore >= 0.6 ? best : null;
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
    await storage.clearEpisodes(feed.url);
    await storage.saveFeeds(feeds);
    notifyListeners();
  }

  Future<void> refreshFeed(Feed feed) async {
    _loading.add(feed.url);
    notifyListeners();
    try {
      final result = await rss.fetch(feed.url);
      _episodes[feed.url] = result.episodes;
      await storage.saveEpisodes(feed.url, result.episodes);
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
  AppLifecycleListener? _lifecycle;

  /// Positie waar het huidige item moet beginnen; tot die bereikt is niets
  /// opslaan (anders overschrijft de 0:00 van het laden je bewaarde plek).
  Duration? _resumeTarget;
  bool _recovering = false;

  /// Laatst gespeelde item, voor "Verder luisteren" na het herstarten van de app.
  MediaItem? get lastPlayed => current == null ? storage.lastPlayed() : null;

  Future<void> forgetLastPlayed() async {
    await storage.setLastPlayed(null);
    notifyListeners();
  }

  Player _createPlayer() {
    final player = Player();
    _subs.add(player.stream.position.listen((pos) {
      final item = current;
      if (item == null) return;
      final target = _resumeTarget;
      if (target != null) {
        if (pos < target - const Duration(seconds: 3)) return;
        _resumeTarget = null;
      }
      // Elke 5 seconden de positie bewaren.
      if (DateTime.now().difference(_lastSave) > const Duration(seconds: 5)) {
        _lastSave = DateTime.now();
        if (pos > const Duration(seconds: 5)) storage.savePosition(item.id, pos);
      }
    }));
    // Bij pauzeren meteen bewaren (bijv. via het vergrendelscherm of koptelefoon).
    _subs.add(player.stream.playing.listen((playing) {
      if (!playing) _saveCurrentPosition();
    }));
    // Verlopen YouTube-stream (na een paar uur pauze) of netwerkfout: opnieuw ophalen
    // en verder vanaf dezelfde plek.
    _subs.add(player.stream.error.listen((_) => _recover()));
    // App naar de achtergrond, scherm uit of afgesloten: positie bewaren.
    _lifecycle = AppLifecycleListener(
      onInactive: _saveCurrentPosition,
      onHide: _saveCurrentPosition,
      onPause: _saveCurrentPosition,
      onDetach: _saveCurrentPosition,
    );
    _subs.add(player.stream.completed.listen((done) async {
      final item = current;
      if (!done || item == null) return;
      await storage.clearPosition(item.id);
      await storage.setLastPlayed(null);
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
    await storage.setLastPlayed(item);
    await _open(uri, storage.position(item.id));
  }

  /// Opent [uri] en zorgt dat hij echt op [start] begint, ook bij streams waar
  /// de startoptie genegeerd wordt.
  Future<void> _open(String uri, Duration? start) async {
    _resumeTarget = start;
    await player.open(Media(uri, start: start));
    await player.setRate(rate);
    if (start == null || start <= const Duration(seconds: 5)) return;
    try {
      await player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 20));
      if (player.state.position < start - const Duration(seconds: 3)) await player.seek(start);
    } on TimeoutException {
      // Geen duur bekend (livestream?): dan maar vanaf het begin.
      _resumeTarget = null;
    }
  }

  /// Na een afspeelfout bij een YouTube-item: stream opnieuw ophalen en
  /// verder vanaf de laatst bekende positie (één keer per fout).
  Future<void> _recover() async {
    final item = current;
    final p = _player;
    if (item == null || p == null || item.youtubeId == null || _recovering) return;
    _recovering = true;
    try {
      final pos = p.state.position > Duration.zero ? p.state.position : storage.position(item.id);
      youtube.invalidate(item.youtubeId!);
      final url = await youtube.streamUrl(item.youtubeId!, audioOnly: item.kind == MediaKind.audio);
      if (identical(current, item)) await _open(url.toString(), pos);
    } catch (_) {
      // Lukt het niet, dan blijft de foutstatus staan; de gebruiker kan opnieuw tikken.
    } finally {
      _recovering = false;
    }
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
    await storage.setLastPlayed(null);
    current = null;
    notifyListeners();
  }

  Future<void> _saveCurrentPosition() async {
    final item = current;
    final p = _player;
    if (item == null || p == null) return;
    final pos = p.state.position;
    // Tijdens het laden/doorspoelen naar de bewaarde plek niet overschrijven.
    final target = _resumeTarget;
    if (target != null && pos < target - const Duration(seconds: 3)) return;
    if (pos > const Duration(seconds: 5)) await storage.savePosition(item.id, pos);
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
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
