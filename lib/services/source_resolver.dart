import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'podcast_directory.dart';
import 'rss_service.dart';
import 'youtube_service.dart';

/// Wat er met een ingevoerde link of zoekterm kan.
sealed class Resolution {
  const Resolution();
}

/// Een RSS/Atom-feed die direct toegevoegd kan worden.
class FeedSource extends Resolution {
  final String feedUrl;

  /// Waar hij gevonden is, bijv. "Apple Podcasts" (voor de melding).
  final String? via;

  /// Als de link naar één aflevering wees: de titel, om die meteen af te spelen.
  final String? episodeTitle;
  const FeedSource(this.feedUrl, {this.via, this.episodeTitle});
}

/// YouTube-kanaal of -playlist (eigen afhandeling met "als podcast").
class YouTubeSource extends Resolution {
  final String input;
  const YouTubeSource(this.input);
}

/// Een of meer podcasts om uit te kiezen (zoekresultaten, of de RSS-versie
/// van een Spotify-podcast). De eerste is de beste match.
class PodcastChoice extends Resolution {
  final List<PodcastMatch> options;
  final String via;
  final String? episodeTitle;

  /// Bijv. de Spotify-link, om toch daar te openen.
  final Uri? openUrl;
  final String? openLabel;
  const PodcastChoice(this.options,
      {required this.via, this.episodeTitle, this.openUrl, this.openLabel});
}

/// Een los audio- of videobestand (of stream) dat de app direct kan afspelen.
class PlayableSource extends Resolution {
  final String url;
  final MediaKind kind;
  final String title;
  const PlayableSource(this.url, this.kind, this.title);
}

/// Niet in deze app af te spelen; eventueel wel elders te openen.
class Unsupported extends Resolution {
  final String message;
  final Uri? openUrl;
  final String? openLabel;
  const Unsupported(this.message, {this.openUrl, this.openLabel});
}

/// Herkent waar een link vandaan komt (YouTube, Spotify, Apple Podcasts,
/// Overcast, een website, een los mediabestand) of zoekt op naam, en zoekt
/// uit hoe het in deze app af te spelen is.
class SourceResolver {
  final http.Client _client;
  final PodcastDirectory directory;
  final RssService _rss;

  SourceResolver({http.Client? client, PodcastDirectory? directory})
      : _client = client ?? http.Client(),
        directory = directory ?? PodcastDirectory(client),
        _rss = RssService(client);

  static const _userAgent = 'Mozilla/5.0 (compatible; Mediaspeler/1.4.1)';
  static const _mediaExt = {
    '.mp3': MediaKind.audio, '.m4a': MediaKind.audio, '.aac': MediaKind.audio,
    '.ogg': MediaKind.audio, '.opus': MediaKind.audio, '.wav': MediaKind.audio,
    '.flac': MediaKind.audio, '.mp4': MediaKind.video, '.m4v': MediaKind.video,
    '.mov': MediaKind.video, '.webm': MediaKind.video, '.mkv': MediaKind.video,
    '.m3u8': MediaKind.video,
  };

  /// Of de invoer een link is (anders: zoeken op naam).
  static bool looksLikeUrl(String input) {
    final s = input.trim();
    if (s.contains(' ')) return false;
    if (s.startsWith(RegExp(r'https?://'))) return true;
    return RegExp(r'^[\w-]+(\.[\w-]+)+(/.*)?$').hasMatch(s);
  }

  Future<Resolution> resolve(String input) async {
    final s = input.trim();
    if (YouTubeService.looksLikeYouTube(s)) return YouTubeSource(s);
    if (!looksLikeUrl(s)) return _searchByName(s);

    final uri = Uri.parse(s.startsWith(RegExp(r'https?://')) ? s : 'https://$s');
    final host = uri.host.toLowerCase();
    if (host == 'open.spotify.com' || host == 'spotify.link' || host == 'spotify.app.link') {
      return _spotify(uri);
    }
    if (host == 'podcasts.apple.com' || host == 'itunes.apple.com') {
      final id = RegExp(r'/id(\d+)').firstMatch(uri.path)?.group(1);
      if (id != null) return _appleLookup(id, episodeId: uri.queryParameters['i']);
    }
    if (host == 'overcast.fm') {
      final id = RegExp(r'^/itunes(\d+)').firstMatch(uri.path)?.group(1);
      if (id != null) return _appleLookup(id, via: 'Overcast');
    }
    return _probe(uri);
  }

  // ---------------- Zoeken op naam ----------------

  Future<Resolution> _searchByName(String term) async {
    final results = await directory.search(term);
    if (results.isEmpty) {
      return Unsupported('Geen podcasts gevonden voor "$term".');
    }
    final ranked = [...results]..sort((a, b) =>
        PodcastDirectory.similarity(term, b.title).compareTo(PodcastDirectory.similarity(term, a.title)));
    return PodcastChoice(dedupe(ranked).take(8).toList(), via: 'Zoekresultaten');
  }

  // ---------------- Spotify ----------------

  /// Spotify heeft geen open feeds, maar de meeste podcasts op Spotify hebben
  /// ook een gewone RSS-feed. We lezen de naam van de openbare Spotify-pagina
  /// en zoeken die op in de podcastgids.
  Future<Resolution> _spotify(Uri uri) async {
    Unsupported open(Uri u) => Unsupported(
          'Deze podcast lijkt alleen op Spotify te staan, en Spotify-afleveringen '
          'kunnen niet buiten de Spotify-app worden afgespeeld.',
          openUrl: u,
          openLabel: 'Open in Spotify',
        );
    final res = await _client
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return open(uri);
    final html = utf8.decode(res.bodyBytes, allowMalformed: true);
    final metas = parseMetaTags(html);
    final title = metas['og:title'];
    final description = metas['og:description'] ?? '';
    final pageUrl = Uri.tryParse(metas['og:url'] ?? '') ?? uri;
    if (title == null) return open(uri);

    final String showName;
    String? author;
    String? episodeTitle;
    if (pageUrl.path.startsWith('/episode/')) {
      // og:description = "<podcast> · Episode"
      showName = description.split(' · ').first.trim();
      episodeTitle = title;
    } else if (pageUrl.path.startsWith('/show/')) {
      // og:description = "Podcast · <maker> · <omschrijving>"
      showName = title;
      final parts = description.split(' · ');
      if (parts.length > 1) author = parts[1].trim();
    } else {
      return Unsupported('Alleen Spotify-links naar een podcast of aflevering worden herkend.',
          openUrl: uri, openLabel: 'Open in Spotify');
    }
    if (showName.isEmpty) return open(pageUrl);

    final results = await directory.search(showName);
    final scored = <PodcastMatch>[];
    for (final r in results) {
      final score = [
        PodcastDirectory.similarity(showName, r.title),
        if (author != null) PodcastDirectory.similarity(author, r.author) * 0.9,
      ].reduce((a, b) => a > b ? a : b);
      if (PodcastDirectory.similarity(showName, r.title) >= PodcastDirectory.minScore) {
        scored.add(PodcastMatch(
            title: r.title, author: r.author, feedUrl: r.feedUrl, imageUrl: r.imageUrl, score: score));
      }
    }
    if (scored.isEmpty) return open(pageUrl);
    scored.sort((a, b) => b.score.compareTo(a.score));
    final unique = dedupe(scored);
    return PodcastChoice(unique.take(3).toList(),
        via: 'Spotify', episodeTitle: episodeTitle, openUrl: pageUrl, openLabel: 'Open in Spotify');
  }

  // ---------------- Apple Podcasts / Overcast ----------------

  Future<Resolution> _appleLookup(String id, {String? episodeId, String via = 'Apple Podcasts'}) async {
    final res = await _client
        .get(Uri.https('itunes.apple.com', '/lookup', {'id': id, 'entity': 'podcast'}))
        .timeout(const Duration(seconds: 15));
    final results = res.statusCode == 200
        ? ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['results'] as List? ?? const [])
        : const [];
    final feed = results
        .cast<Map>()
        .map((r) => r['feedUrl'])
        .whereType<String>()
        .firstOrNull;
    if (feed == null) {
      return Unsupported('Deze podcast heeft geen openbare feed (bijv. alleen voor abonnees).',
          openUrl: Uri.parse('https://podcasts.apple.com/podcast/id$id'),
          openLabel: 'Open in Apple Podcasts');
    }
    String? episodeTitle;
    if (episodeId != null) {
      try {
        final ep = await _client.get(Uri.https('itunes.apple.com', '/lookup',
            {'id': episodeId, 'entity': 'podcastEpisode'}));
        final r = (jsonDecode(utf8.decode(ep.bodyBytes)) as Map)['results'] as List? ?? const [];
        episodeTitle = r
            .cast<Map>()
            .where((e) => e['kind'] == 'podcast-episode' || e['wrapperType'] == 'podcastEpisode')
            .map((e) => e['trackName'])
            .whereType<String>()
            .firstOrNull;
      } catch (_) {}
    }
    return FeedSource(feed, via: via, episodeTitle: episodeTitle);
  }

  // ---------------- Overige links ----------------

  /// Kijkt wat er achter een link zit: een feed, een mediabestand, of een
  /// webpagina met een feed of media erin.
  Future<Resolution> _probe(Uri uri) async {
    final ext = _extension(uri.path);
    if (_mediaExt.containsKey(ext)) {
      return PlayableSource(uri.toString(), _mediaExt[ext]!, _fileName(uri));
    }

    final req = http.Request('GET', uri)
      ..headers['User-Agent'] = _userAgent
      ..headers['Accept'] =
          'application/rss+xml, application/atom+xml, application/xml, text/html, */*';
    final http.StreamedResponse res;
    try {
      res = await _client.send(req).timeout(const Duration(seconds: 15));
    } catch (e) {
      return Unsupported('Kon de link niet openen ($e).');
    }
    if (res.statusCode >= 400) {
      unawaited(res.stream.drain<void>().catchError((_) {}));
      return Unsupported('De link gaf HTTP ${res.statusCode}.');
    }
    final type = (res.headers['content-type'] ?? '').toLowerCase();
    final finalUrl = res.request?.url ?? uri;

    if (type.startsWith('audio/') || type.startsWith('video/') || type.contains('mpegurl')) {
      // Niet het hele bestand downloaden: alleen het type was nodig.
      unawaited(res.stream.listen(null).cancel());
      final kind = type.startsWith('audio/') ? MediaKind.audio : MediaKind.video;
      return PlayableSource(finalUrl.toString(), kind, _fileName(finalUrl));
    }

    final body = await _readLimited(res.stream, 1024 * 1024);
    final head = body.trimLeft().toLowerCase();
    final looksXml = head.startsWith('<?xml') || head.startsWith('<rss') || head.startsWith('<feed');
    if (type.contains('xml') || looksXml) {
      if (head.contains('<rss') || head.contains('<feed') || head.contains('<channel')) {
        return FeedSource(finalUrl.toString());
      }
    }
    if (type.contains('html') || head.startsWith('<!doctype html') || head.contains('<html')) {
      return _fromHtml(body, finalUrl);
    }
    return Unsupported('Dit type link wordt niet herkend ($type).',
        openUrl: finalUrl, openLabel: 'Open in browser');
  }

  /// Een webpagina: zoek (in deze volgorde) een podcastfeed die de pagina
  /// aankondigt, een link naar Apple Podcasts, een feed-achtige link, of
  /// losse media op de pagina. Anders: zoeken op de naam van de pagina.
  Future<Resolution> _fromHtml(String html, Uri pageUrl) async {
    final feeds = [...discoverFeeds(html, pageUrl), ...feedLikeLinks(html, pageUrl)];
    for (final feed in feeds.toSet().take(5)) {
      // Websites kondigen vaak hun nieuwsfeed aan: alleen nemen als er media in staat.
      if (await _hasEpisodes(feed)) return FeedSource(feed.toString(), via: 'de website');
    }
    for (final id in appleIds(html).take(2)) {
      final r = await _appleLookup(id, via: 'de website (Apple Podcasts-link)');
      if (r is FeedSource) return r;
    }

    final metas = parseMetaTags(html);
    for (final key in const ['og:audio', 'og:audio:url', 'og:video:url', 'og:video']) {
      final media = metas[key];
      if (media != null && media.startsWith('http')) {
        final kind = key.contains('audio') ? MediaKind.audio : MediaKind.video;
        return PlayableSource(pageUrl.resolve(media).toString(), kind,
            metas['og:title'] ?? _fileName(pageUrl));
      }
    }

    final name = metas['og:site_name'] ?? metas['og:title'] ?? pageTitle(html);
    if (name != null && name.trim().isNotEmpty) {
      final results = await directory.search(name);
      final close = dedupe(results
          .where((r) =>
              PodcastDirectory.similarity(name, r.title) >= 0.5 ||
              PodcastDirectory.similarity(name, r.author) >= 0.5)
          .toList());
      if (close.isNotEmpty) {
        return PodcastChoice(close.take(4).toList(),
            via: 'Zoekresultaten', openUrl: pageUrl, openLabel: 'Open in browser');
      }
    }
    return Unsupported('Op deze pagina staat geen podcastfeed of afspeelbaar bestand.',
        openUrl: pageUrl, openLabel: 'Open in browser');
  }

  Future<bool> _hasEpisodes(Uri feed) async {
    try {
      return (await _rss.fetch(feed.toString())).episodes.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Zelfde podcast vaak meerdere keren in de gids (of NL + US): één per feed / titel+maker.
  static List<PodcastMatch> dedupe(List<PodcastMatch> list) {
    final seen = <String>{};
    return [
      for (final m in list)
        if (seen.add(m.feedUrl.toLowerCase().replaceFirst(RegExp(r'^https?://'), '')) &&
            seen.add('${m.title.toLowerCase()}|${m.author.toLowerCase()}'))
          m,
    ];
  }

  /// Apple Podcasts-id's uit links op een pagina.
  static Iterable<String> appleIds(String html) => RegExp(
          r'''(?:podcasts|itunes)\.apple\.com/[^"'\s<>]*?/id(\d+)''')
      .allMatches(html)
      .map((m) => m.group(1)!)
      .toSet();

  /// Links die op een podcastfeed lijken (bijv. `/feed/podcast/`, `….rss`).
  static List<Uri> feedLikeLinks(String html, Uri base) {
    final out = <Uri>[];
    for (final m in RegExp(r'''href\s*=\s*["']([^"']+)["']''', caseSensitive: false)
        .allMatches(html)) {
      final href = _unescape(m.group(1)!);
      final l = href.toLowerCase();
      final podcasty = l.contains('/feed/podcast') ||
          l.contains('feeds.') ||
          l.endsWith('.rss') ||
          l.endsWith('/rss') ||
          (l.endsWith('.xml') && l.contains('podcast'));
      if (!podcasty || l.startsWith('mailto:') || l.contains('comments')) continue;
      final u = Uri.tryParse(href);
      if (u != null) out.add(base.resolveUri(u));
    }
    return out;
  }

  static String? pageTitle(String html) {
    final m = RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false).firstMatch(html);
    final t = m == null ? null : _unescape(m.group(1)!).trim();
    if (t == null || t.isEmpty) return null;
    // "Aflevering 12 – Mijn Podcast" / "Mijn Podcast | Site": neem het langste stuk.
    final parts = t.split(RegExp(r'\s[|–—-]\s'));
    parts.sort((a, b) => b.length.compareTo(a.length));
    return parts.first.trim();
  }

  static Future<String> _readLimited(Stream<List<int>> stream, int max) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
      if (bytes.length >= max) break;
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _extension(String path) {
    final p = path.toLowerCase();
    final dot = p.lastIndexOf('.');
    return dot < 0 || dot < p.lastIndexOf('/') ? '' : p.substring(dot);
  }

  static String _fileName(Uri uri) {
    final last = uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
    return last != null ? Uri.decodeComponent(last) : uri.host;
  }

  // ---------------- HTML-hulpjes ----------------

  static final _tag = RegExp(r'<(meta|link)\b[^>]*>', caseSensitive: false);
  static final _attr = RegExp(r'''([\w:-]+)\s*=\s*("([^"]*)"|'([^']*)')''');

  static Map<String, String> _attrs(String tag) => {
        for (final m in _attr.allMatches(tag))
          m.group(1)!.toLowerCase(): _unescape(m.group(3) ?? m.group(4) ?? ''),
      };

  /// `<meta property|name="…" content="…">` als map (eerste waarde wint).
  static Map<String, String> parseMetaTags(String html) {
    final out = <String, String>{};
    for (final m in _tag.allMatches(html)) {
      if (m.group(1)!.toLowerCase() != 'meta') continue;
      final a = _attrs(m.group(0)!);
      final key = a['property'] ?? a['name'];
      final content = a['content'];
      if (key != null && content != null) out.putIfAbsent(key.toLowerCase(), () => content);
    }
    return out;
  }

  /// RSS-autodiscovery: `<link rel="alternate" type="application/rss+xml" href="…">`.
  static List<Uri> discoverFeeds(String html, Uri base) {
    final podcast = <Uri>[], other = <Uri>[];
    for (final m in _tag.allMatches(html)) {
      if (m.group(1)!.toLowerCase() != 'link') continue;
      final a = _attrs(m.group(0)!);
      final type = (a['type'] ?? '').toLowerCase();
      if (!(a['rel'] ?? '').toLowerCase().contains('alternate') ||
          (type != 'application/rss+xml' && type != 'application/atom+xml') ||
          a['href'] == null) {
        continue;
      }
      // Commentaarfeeds (WordPress) overslaan; feeds met "podcast" in de naam eerst.
      final title = (a['title'] ?? '').toLowerCase();
      if (title.contains('comment') || title.contains('reacties')) continue;
      final url = base.resolve(a['href']!);
      (title.contains('podcast') || url.path.contains('podcast') ? podcast : other).add(url);
    }
    return [...podcast, ...other];
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x27;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}
