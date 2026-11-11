import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mediaspeler/models.dart';
import 'package:mediaspeler/services/source_resolver.dart';

const _podcastFeed = '''<rss><channel><title>Mijn Podcast</title>
<item><title>Aflevering 3: Over testen</title><guid>e3</guid>
<enclosure url="https://cdn.example/e3.mp3" type="audio/mpeg"/></item>
</channel></rss>''';

const _newsFeed = '''<rss><channel><title>Nieuws</title>
<item><title>Bericht</title><link>https://site.example/b</link></item>
</channel></rss>''';

String _itunes(List<Map<String, dynamic>> results) =>
    jsonEncode({'resultCount': results.length, 'results': results});

Map<String, dynamic> _pod(String title, String author, String feed) =>
    {'collectionName': title, 'artistName': author, 'feedUrl': feed};

/// Nep-internet: per URL een antwoord.
SourceResolver _resolver(Map<String, http.Response Function(http.Request)> routes,
    {List<Uri>? log}) {
  final client = MockClient((req) async {
    log?.add(req.url);
    final key = req.url.replace(query: '').toString().replaceAll(RegExp(r'\?$'), '');
    for (final e in routes.entries) {
      if (key == e.key || req.url.toString() == e.key) return e.value(req);
    }
    if (req.url.host == 'itunes.apple.com' && routes.containsKey('itunes:${req.url.path}')) {
      return routes['itunes:${req.url.path}']!(req);
    }
    return http.Response('niet gevonden', 404);
  });
  return SourceResolver(client: client);
}

http.Response _html(String body) =>
    http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': 'text/html; charset=utf-8'});
http.Response _xml(String body) =>
    http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': 'application/rss+xml'});
http.Response _json(String body) =>
    http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': 'application/json'});

void main() {
  group('looksLikeUrl', () {
    test('links en namen', () {
      expect(SourceResolver.looksLikeUrl('https://x.nl/feed'), isTrue);
      expect(SourceResolver.looksLikeUrl('podcast.example.com/rss'), isTrue);
      expect(SourceResolver.looksLikeUrl('lex fridman'), isFalse);
      expect(SourceResolver.looksLikeUrl('Radiolab'), isFalse);
    });
  });

  test('YouTube wordt doorgegeven aan de YouTube-afhandeling', () async {
    final r = await _resolver({}).resolve('youtube.com/@kanaal');
    expect(r, isA<YouTubeSource>());
  });

  test('naam: zoekresultaten uit de podcastgids, zonder dubbelen', () async {
    final r = await _resolver({
      'itunes:/search': (_) => _json(_itunes([
            _pod('Mijn Podcast', 'Ik', 'https://feed.example/a'),
            _pod('Mijn Podcast', 'Ik', 'http://feed.example/a'),
            _pod('Iets anders', 'Jij', 'https://feed.example/b'),
          ])),
    }).resolve('mijn podcast');
    expect(r, isA<PodcastChoice>());
    final c = r as PodcastChoice;
    expect(c.options.map((o) => o.feedUrl), ['https://feed.example/a', 'https://feed.example/b']);
    expect(c.via, 'Zoekresultaten');
  });

  group('Spotify', () {
    test('show: naam van de pagina, RSS-versie uit de gids', () async {
      final r = await _resolver({
        'https://open.spotify.com/show/abc': (_) => _html(
            '<meta property="og:title" content="Mijn Podcast"/>'
            '<meta property="og:description" content="Podcast · Ik · Over dingen"/>'
            '<meta property="og:url" content="https://open.spotify.com/show/abc"/>'),
        'itunes:/search': (_) => _json(_itunes([_pod('Mijn Podcast', 'Ik', 'https://feed.example/a')])),
      }).resolve('https://open.spotify.com/show/abc?si=123');
      final c = r as PodcastChoice;
      expect(c.via, 'Spotify');
      expect(c.options.single.feedUrl, 'https://feed.example/a');
      expect(c.episodeTitle, isNull);
      expect(c.openUrl.toString(), 'https://open.spotify.com/show/abc');
    });

    test('aflevering: podcastnaam uit de beschrijving en de titel van de aflevering', () async {
      final r = await _resolver({
        'https://open.spotify.com/episode/xyz': (_) => _html(
            '<meta property="og:title" content="Aflevering 3: Over testen"/>'
            '<meta property="og:description" content="Mijn Podcast · Episode"/>'
            '<meta property="og:url" content="https://open.spotify.com/episode/xyz"/>'),
        'itunes:/search': (_) => _json(_itunes([_pod('Mijn Podcast', 'Ik', 'https://feed.example/a')])),
      }).resolve('https://open.spotify.com/episode/xyz');
      final c = r as PodcastChoice;
      expect(c.episodeTitle, 'Aflevering 3: Over testen');
      expect(c.options.single.title, 'Mijn Podcast');
    });

    test('alleen op Spotify: melding met "Open in Spotify"', () async {
      final r = await _resolver({
        'https://open.spotify.com/show/excl': (_) => _html(
            '<meta property="og:title" content="Exclusieve Show"/>'
            '<meta property="og:url" content="https://open.spotify.com/show/excl"/>'),
        'itunes:/search': (_) => _json(_itunes([])),
      }).resolve('https://open.spotify.com/show/excl');
      final u = r as Unsupported;
      expect(u.openLabel, 'Open in Spotify');
      expect(u.message, contains('alleen op Spotify'));
    });
  });

  test('Apple Podcasts: feed via de lookup, inclusief aflevering', () async {
    final r = await _resolver({
      'itunes:/lookup': (req) => req.url.queryParameters['id'] == '123'
          ? _json(_itunes([_pod('Mijn Podcast', 'Ik', 'https://feed.example/a')]))
          : _json(jsonEncode({
              'results': [
                {'wrapperType': 'podcastEpisode', 'kind': 'podcast-episode', 'trackName': 'Aflevering 3'}
              ]
            })),
    }).resolve('https://podcasts.apple.com/nl/podcast/mijn-podcast/id123?i=456');
    final f = r as FeedSource;
    expect(f.feedUrl, 'https://feed.example/a');
    expect(f.via, 'Apple Podcasts');
    expect(f.episodeTitle, 'Aflevering 3');
  });

  test('Overcast-link via het Apple-id', () async {
    final r = await _resolver({
      'itunes:/lookup': (_) => _json(_itunes([_pod('Mijn Podcast', 'Ik', 'https://feed.example/a')])),
    }).resolve('https://overcast.fm/itunes123/mijn-podcast');
    expect((r as FeedSource).via, 'Overcast');
  });

  group('websites en bestanden', () {
    test('een RSS-feed zelf', () async {
      final r = await _resolver({'https://feed.example/a': (_) => _xml(_podcastFeed)})
          .resolve('https://feed.example/a');
      expect((r as FeedSource).feedUrl, 'https://feed.example/a');
    });

    test('mediabestand op extensie: direct afspeelbaar zonder te downloaden', () async {
      final log = <Uri>[];
      final r = await _resolver({}, log: log).resolve('https://cdn.example/map/mijn%20audio.mp3');
      final p = r as PlayableSource;
      expect(p.kind, MediaKind.audio);
      expect(p.title, 'mijn audio.mp3');
      expect(log, isEmpty);
    });

    test('mediabestand op content-type', () async {
      final r = await _resolver({
        'https://cdn.example/stream': (_) =>
            http.Response('', 200, headers: {'content-type': 'video/mp4'}),
      }).resolve('https://cdn.example/stream');
      expect((r as PlayableSource).kind, MediaKind.video);
    });

    test('pagina met nieuwsfeed én podcastfeed: kiest de feed met afleveringen', () async {
      final r = await _resolver({
        'https://site.example/podcast': (_) => _html('''<html><head>
          <link rel="alternate" type="application/rss+xml" title="Nieuws" href="/feed/">
          <link rel="alternate" type="application/rss+xml" title="Reacties" href="/comments/feed/">
          </head><body><a href="/feed/podcast/">Abonneren</a></body></html>'''),
        'https://site.example/feed/': (_) => _xml(_newsFeed),
        'https://site.example/feed/podcast/': (_) => _xml(_podcastFeed),
      }).resolve('https://site.example/podcast');
      expect((r as FeedSource).feedUrl, 'https://site.example/feed/podcast/');
    });

    test('pagina met alleen een Apple Podcasts-link', () async {
      final r = await _resolver({
        'https://site.example/show': (_) => _html(
            '<html><a href="https://podcasts.apple.com/us/podcast/x/id999">Apple</a></html>'),
        'itunes:/lookup': (_) => _json(_itunes([_pod('X', 'Y', 'https://feed.example/x')])),
      }).resolve('https://site.example/show');
      expect((r as FeedSource).feedUrl, 'https://feed.example/x');
    });

    test('pagina met og:audio: direct afspeelbaar', () async {
      final r = await _resolver({
        'https://site.example/ep': (_) => _html('<html><head>'
            '<meta property="og:title" content="Losse aflevering">'
            '<meta property="og:audio" content="https://cdn.example/ep.mp3"></head></html>'),
      }).resolve('https://site.example/ep');
      final p = r as PlayableSource;
      expect(p.url, 'https://cdn.example/ep.mp3');
      expect(p.title, 'Losse aflevering');
    });

    test('pagina zonder feed: zoeken op de naam van de site', () async {
      final r = await _resolver({
        'https://site.example/': (_) =>
            _html('<html><head><title>Mijn Podcast | Home</title></head></html>'),
        'itunes:/search': (_) => _json(_itunes([_pod('Mijn Podcast', 'Ik', 'https://feed.example/a')])),
      }).resolve('https://site.example/');
      expect((r as PodcastChoice).options.single.feedUrl, 'https://feed.example/a');
    });

    test('HTTP-fout', () async {
      final r = await _resolver({}).resolve('https://site.example/weg');
      expect((r as Unsupported).message, contains('404'));
    });
  });

  test('HTML-hulpjes', () {
    expect(SourceResolver.pageTitle('<title>Afl. 12 – Mijn Podcast &amp; Zo</title>'),
        'Mijn Podcast & Zo');
    expect(SourceResolver.appleIds('href="https://podcasts.apple.com/nl/podcast/a/id1?x" '
            'href="https://itunes.apple.com/podcast/id2"'),
        {'1', '2'});
    final metas = SourceResolver.parseMetaTags(
        "<meta content='B' property='og:title'><meta name=\"description\" content=\"C &quot;x&quot;\">");
    expect(metas['og:title'], 'B');
    expect(metas['description'], 'C "x"');
  });
}
