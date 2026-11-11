import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models.dart';

/// Resultaat van het herleiden van een YouTube-link naar een RSS-feed.
class YouTubeFeedRef {
  final String feedUrl;
  final String? title;
  final String? imageUrl;
  /// Bijv. `@kanaal`, als die uit de link bekend is (helpt bij het zoeken van de podcastversie).
  final String? handle;
  const YouTubeFeedRef(this.feedUrl, {this.title, this.imageUrl, this.handle});
}

/// Een beschikbare audiostream (voor de keuze van de zuinigste geschikte stream).
class AudioOption {
  final Uri url;
  final int bitsPerSecond;
  const AudioOption(this.url, this.bitsPerSecond);
}

/// YouTube-ondersteuning:
/// - kanaal- en playlistlinks omzetten naar YouTube's eigen RSS-feed;
/// - bij afspelen de stream-URL ophalen, bij [audioOnly] alleen de audio.
class YouTubeService {
  static const feedBase = 'https://www.youtube.com/feeds/videos.xml';

  /// Audio tot ~96 kbit/s is ruim voldoende voor spraak en muziek op de telefoon.
  static const maxAudioBitrate = 96000;

  /// YouTube-stream-URL's verlopen na een paar uur; zo lang hergebruiken we ze.
  static const _cacheFor = Duration(hours: 4);

  YoutubeExplode? _yt;
  YoutubeExplode get _client => _yt ??= YoutubeExplode();
  final Map<String, (Uri, DateTime)> _cache = {};

  /// Of de invoer een YouTube-kanaal, -handle of -playlist lijkt.
  static bool looksLikeYouTube(String input) {
    final s = input.trim();
    return s.startsWith('@') || isYouTubeUrl(_withScheme(s));
  }

  /// Zet links die zonder netwerk te herleiden zijn direct om naar de feed-URL:
  /// `/channel/UC…`, `?list=…` (playlist) en bestaande `feeds/videos.xml`-links.
  static String? directFeedUrl(String input) {
    final s = _withScheme(input.trim());
    if (!isYouTubeUrl(s)) return null;
    final uri = Uri.parse(s);
    final seg = uri.pathSegments;
    if (seg.length >= 2 && seg[0] == 'feeds' && seg[1] == 'videos.xml') {
      final ch = uri.queryParameters['channel_id'];
      final pl = uri.queryParameters['playlist_id'];
      if (ch != null) return '$feedBase?channel_id=$ch';
      if (pl != null) return '$feedBase?playlist_id=$pl';
    }
    final list = uri.queryParameters['list'];
    if (list != null && list.isNotEmpty) {
      return '$feedBase?playlist_id=$list';
    }
    if (seg.length >= 2 && seg[0] == 'channel' && ChannelId.validateChannelId(seg[1])) {
      return '$feedBase?channel_id=${seg[1]}';
    }
    return null;
  }

  /// Herleidt een kanaal-link, `@handle` of playlist naar de RSS-feed van YouTube.
  Future<YouTubeFeedRef> resolveFeed(String input) async {
    final direct = directFeedUrl(input);
    if (direct != null) return YouTubeFeedRef(direct);
    final key = input.trim().toLowerCase();
    return _resolved[key] ??= await _resolveViaYouTube(input);
  }

  final Map<String, YouTubeFeedRef> _resolved = {};

  Future<YouTubeFeedRef> _resolveViaYouTube(String input) async {
    final s = input.trim();
    try {
      final Channel channel;
      String? handle;
      if (s.startsWith('@')) {
        handle = s;
        channel = await _client.channels.getByHandle(s);
      } else {
        final seg = Uri.parse(_withScheme(s)).pathSegments;
        if (seg.isNotEmpty && seg.first.startsWith('@')) {
          handle = seg.first;
          channel = await _client.channels.getByHandle(seg.first);
        } else if (seg.length >= 2 && seg.first == 'user') {
          handle = seg[1];
          channel = await _client.channels.getByUsername(seg[1]);
        } else if (seg.length >= 2 && seg.first == 'c') {
          handle = seg[1];
          channel = await _client.channels.getByHandle('@${seg[1]}');
        } else if (youtubeVideoId(_withScheme(s)) != null) {
          throw const YouTubeException(
              'Dit is een link naar één video. Plak de link van het kanaal (bijv. youtube.com/@naam).');
        } else {
          throw const YouTubeException('Onbekende YouTube-link. Gebruik een kanaal- of playlistlink.');
        }
      }
      return YouTubeFeedRef(
        '$feedBase?channel_id=${channel.id.value}',
        title: channel.title,
        imageUrl: channel.logoUrl.isNotEmpty ? channel.logoUrl : null,
        handle: handle,
      );
    } on YouTubeException {
      rethrow;
    } catch (e) {
      throw YouTubeException(e is FatalFailureException || e is SearchItemSectionException
          ? 'YouTube-kanaal niet gevonden. Controleer de link of @naam.'
          : 'Kon het YouTube-kanaal niet vinden ($e)');
    }
  }

  /// De stream-URL om af te spelen. Bij [audioOnly] alleen een audiostream
  /// (scheelt meestal 70–90% dataverbruik ten opzichte van video).
  Future<Uri> streamUrl(String videoId, {required bool audioOnly}) async {
    final key = '$videoId:${audioOnly ? 'a' : 'v'}';
    final cached = _cache[key];
    if (cached != null && now().difference(cached.$2) < _cacheFor) return cached.$1;

    // Rustig aan doen: tijdens een blokkade of voor een onspeelbare video
    // vragen we YouTube niets, maar melden we het direct (de app valt dan terug).
    final until = _blockedUntil;
    if (until != null && now().isBefore(until)) throw const YouTubeBlockedException();
    if (_unplayable.contains(videoId)) {
      throw const YouTubeException('Deze video kan hier niet worden afgespeeld.');
    }

    Uri url;
    try {
      url = await fetchStream(videoId, audioOnly: audioOnly);
    } on YouTubeBlockedException {
      // Eén keer opnieuw na een korte pauze; daarna een tijd met rust laten.
      await sleep(retryDelay);
      try {
        url = await fetchStream(videoId, audioOnly: audioOnly);
      } on YouTubeBlockedException {
        _blockedUntil = now().add(cooldown);
        rethrow;
      }
    } on YouTubeException {
      _unplayable.add(videoId);
      rethrow;
    }
    _blockedUntil = null;
    _cache[key] = (url, now());
    return url;
  }

  /// Vergeet een (verlopen) stream-URL, zodat de volgende keer een verse wordt opgehaald.
  void invalidate(String videoId) =>
      _cache.removeWhere((key, _) => key.startsWith('$videoId:'));

  static const retryDelay = Duration(seconds: 4);
  static const cooldown = Duration(minutes: 15);
  DateTime? _blockedUntil;
  final Set<String> _unplayable = {};

  /// Of YouTube ons op dit moment blokkeert (dan meteen de officiële speler gebruiken).
  bool get isBlocked => _blockedUntil != null && now().isBefore(_blockedUntil!);

  /// Overschrijfbaar in tests.
  DateTime now() => DateTime.now();
  Future<void> sleep(Duration d) => Future.delayed(d);

  /// Haalt de stream-URL op bij YouTube (één poging, zonder cache).
  Future<Uri> fetchStream(String videoId, {required bool audioOnly}) async {
    final StreamManifest manifest;
    try {
      manifest = await _client.videos.streamsClient.getManifest(
        videoId,
        ytClients: [YoutubeApiClient.ios, YoutubeApiClient.androidVr],
        requireWatchPage: false,
      );
    } on VideoUnavailableException {
      // Komt ook voor bij recente video's die wel bestaan; de officiële speler kan ze vaak wel.
      throw const YouTubeException('YouTube geeft deze video niet vrij als losse stream.');
    } on VideoUnplayableException catch (e) {
      if (e.message.contains('not a bot')) throw const YouTubeBlockedException();
      throw const YouTubeException('Deze video kan hier niet worden afgespeeld.');
    } catch (e) {
      throw YouTubeException('Kon de YouTube-stream niet ophalen ($e)');
    }

    if (audioOnly) {
      final pick = pickAudio([
        for (final a in manifest.audioOnly) AudioOption(a.url, a.bitrate.bitsPerSecond),
      ]);
      if (pick == null) throw const YouTubeException('Geen audiostream gevonden voor deze video.');
      return pick.url;
    }
    if (manifest.muxed.isNotEmpty) return manifest.muxed.withHighestBitrate().url;
    throw const YouTubeException('Geen videostream gevonden voor deze video.');
  }

  /// Kiest de beste audiostream tot [maxAudioBitrate]; anders de zuinigste.
  static AudioOption? pickAudio(List<AudioOption> options) {
    if (options.isEmpty) return null;
    final sorted = [...options]..sort((a, b) => a.bitsPerSecond.compareTo(b.bitsPerSecond));
    final within = sorted.where((o) => o.bitsPerSecond <= maxAudioBitrate);
    return within.isNotEmpty ? within.last : sorted.first;
  }

  void close() => _yt?.close();

  static String _withScheme(String s) => s.startsWith(RegExp(r'https?://')) ? s : 'https://$s';
}

class YouTubeException implements Exception {
  final String message;
  const YouTubeException(this.message);
  @override
  String toString() => message;
}

/// YouTube weigert het ophalen ("bevestig dat je geen bot bent").
class YouTubeBlockedException extends YouTubeException {
  const YouTubeBlockedException()
      : super('YouTube blokkeert het ophalen van alleen de audio tijdelijk.');
}
