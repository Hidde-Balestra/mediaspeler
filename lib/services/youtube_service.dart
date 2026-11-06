import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models.dart';

/// Resultaat van het herleiden van een YouTube-link naar een RSS-feed.
class YouTubeFeedRef {
  final String feedUrl;
  final String? title;
  final String? imageUrl;
  const YouTubeFeedRef(this.feedUrl, {this.title, this.imageUrl});
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

    final s = input.trim();
    try {
      final Channel channel;
      if (s.startsWith('@')) {
        channel = await _client.channels.getByHandle(s);
      } else {
        final seg = Uri.parse(_withScheme(s)).pathSegments;
        if (seg.isNotEmpty && seg.first.startsWith('@')) {
          channel = await _client.channels.getByHandle(seg.first);
        } else if (seg.length >= 2 && seg.first == 'user') {
          channel = await _client.channels.getByUsername(seg[1]);
        } else if (seg.length >= 2 && seg.first == 'c') {
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
      );
    } on YouTubeException {
      rethrow;
    } catch (e) {
      throw YouTubeException('Kon het YouTube-kanaal niet vinden ($e)');
    }
  }

  /// De stream-URL om af te spelen. Bij [audioOnly] alleen een audiostream
  /// (scheelt meestal 70–90% dataverbruik ten opzichte van video).
  Future<Uri> streamUrl(String videoId, {required bool audioOnly}) async {
    final key = '$videoId:${audioOnly ? 'a' : 'v'}';
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.$2) < _cacheFor) return cached.$1;

    final StreamManifest manifest;
    try {
      manifest = await _client.videos.streamsClient.getManifest(
        videoId,
        ytClients: [YoutubeApiClient.ios, YoutubeApiClient.androidVr],
        requireWatchPage: false,
      );
    } on VideoUnplayableException catch (e) {
      final msg = e.message.contains('not a bot')
          ? 'YouTube blokkeert het ophalen tijdelijk (bot-controle). Probeer het later opnieuw.'
          : 'Deze video kan hier niet worden afgespeeld.';
      throw YouTubeException(msg);
    } catch (e) {
      throw YouTubeException('Kon de YouTube-stream niet ophalen ($e)');
    }

    final Uri url;
    if (audioOnly) {
      final pick = pickAudio([
        for (final a in manifest.audioOnly) AudioOption(a.url, a.bitrate.bitsPerSecond),
      ]);
      if (pick == null) throw const YouTubeException('Geen audiostream gevonden voor deze video.');
      url = pick.url;
    } else if (manifest.muxed.isNotEmpty) {
      url = manifest.muxed.withHighestBitrate().url;
    } else {
      throw const YouTubeException(
          'Geen videostream gevonden. Zet "Alleen audio" aan of open de video in YouTube.');
    }
    _cache[key] = (url, DateTime.now());
    return url;
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
