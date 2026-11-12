import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mediaspeler/main.dart';
import 'package:mediaspeler/models.dart';
import 'package:mediaspeler/screens/feed_detail_screen.dart';
import 'package:mediaspeler/screens/player_screen.dart';
import 'package:mediaspeler/services/app_state.dart';
import 'package:mediaspeler/services/podcast_directory.dart';
import 'package:mediaspeler/services/rss_service.dart';
import 'package:mediaspeler/services/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const _feedUrl = 'https://pod.example/rss';
const _ytUrl = 'https://www.youtube.com/feeds/videos.xml?channel_id=UCtest';

late FakeEngine engine;

/// App-status met een podcast (2 afleveringen) en een YouTube-kanaal, al opgehaald.
Future<AppState> _state({List<Map<String, Object?>> localVideos = const []}) async {
  final now = DateTime.now().toIso8601String();
  SharedPreferences.setMockInitialValues({
    'feeds': jsonEncode([
      {'url': _feedUrl, 'title': 'Testpodcast', 'description': 'Over testen', 'lastFetched': now},
      {'url': _ytUrl, 'title': 'Testkanaal', 'lastFetched': now, 'audioOnly': true},
    ]),
    'eps:$_feedUrl': jsonEncode([
      {'id': 'p1', 'feedUrl': _feedUrl, 'title': 'Eerste aflevering', 'mediaUrl': 'https://pod.example/1.mp3',
        'mimeType': 'audio/mpeg', 'published': now, 'duration': 1800, 'description': 'Uitleg'},
      {'id': 'p2', 'feedUrl': _feedUrl, 'title': 'Video-aflevering', 'mediaUrl': 'https://pod.example/2.mp4',
        'mimeType': 'video/mp4', 'published': now},
    ]),
    'eps:$_ytUrl': jsonEncode([
      {'id': 'yt:video:dQw4w9WgXcQ', 'feedUrl': _ytUrl, 'title': 'YouTube-video',
        'mediaUrl': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', 'mimeType': 'video/youtube', 'published': now},
    ]),
    'local_videos': jsonEncode(localVideos),
  });
  engine = FakeEngine();
  return AppState(await Storage.open(),
      rss: RssService(MockClient((_) async => http.Response('', 500))),
      youtube: FakeYouTube(),
      podcasts: FakePodcasts(),
      engine: () => engine);
}

Future<void> _openFeed(WidgetTester tester, AppState state, String url) async {
  await tester.pumpWidget(MediaspelerApp(state: state));
  await tester.pumpAndSettle();
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  nav.push(MaterialPageRoute(builder: (_) => FeedDetailScreen(feed: state.feedByUrl(url)!)));
  await tester.pumpAndSettle();
}

void main() {
  group('feed-detail', () {
    testWidgets('toont beschrijving en afleveringen met datum en duur', (tester) async {
      final state = await _state();
      await _openFeed(tester, state, _feedUrl);
      expect(find.text('Over testen'), findsOneWidget);
      expect(find.text('Eerste aflevering'), findsOneWidget);
      expect(find.textContaining('30:00'), findsOneWidget);
    });

    testWidgets('afspelen van audio: mini-speler verschijnt, geen speler-scherm', (tester) async {
      final state = await _state();
      await _openFeed(tester, state, _feedUrl);
      await tester.tap(find.byTooltip('Afspelen').first);
      await tester.pumpAndSettle();
      expect(engine.opened.single.$1, 'https://pod.example/1.mp3');
      expect(find.byType(PlayerScreen), findsNothing);
      expect(find.byIcon(Icons.equalizer), findsOneWidget, reason: 'speelt nu');
    });

    testWidgets('afspelen van video opent het speler-scherm', (tester) async {
      final state = await _state();
      await _openFeed(tester, state, _feedUrl);
      await tester.tap(find.byTooltip('Afspelen').at(1));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsOneWidget);
    });

    testWidgets('details: als beluisterd markeren', (tester) async {
      final state = await _state();
      await _openFeed(tester, state, _feedUrl);
      await tester.tap(find.text('Eerste aflevering'));
      await tester.pumpAndSettle();
      expect(find.text('Uitleg'), findsOneWidget);
      await tester.tap(find.text('Markeer als beluisterd'));
      await tester.pumpAndSettle();
      expect(state.finished, contains('p1'));
      expect(find.textContaining('beluisterd'), findsOneWidget);
    });

    testWidgets('YouTube als podcast: audio-knop, en omzetten naar video', (tester) async {
      final state = await _state();
      await _openFeed(tester, state, _ytUrl);
      expect(find.byIcon(Icons.headphones), findsWidgets);

      await tester.tap(find.text('YouTube-video'));
      await tester.pumpAndSettle();
      expect(find.text('Luisteren (alleen audio)'), findsOneWidget);
      expect(find.text('Video bekijken'), findsOneWidget);
      await tester.tap(find.text('Luisteren (alleen audio)'));
      await tester.pumpAndSettle();
      expect(state.current!.kind, MediaKind.audio);

      await tester.tap(find.byTooltip('Alleen audio (tik voor video met beeld)'));
      await tester.pumpAndSettle();
      expect(state.feedByUrl(_ytUrl)!.audioOnly, isFalse);
      expect(find.text('Afspelen als video met beeld'), findsOneWidget);
    });
  });

  group('spelers', () {
    testWidgets('mini-speler: pauze, openen van het speler-scherm en stoppen', (tester) async {
      final state = await _state();
      await tester.pumpWidget(MediaspelerApp(state: state));
      await state.play(MediaItem.fromEpisode(state.episodesFor(_feedUrl)!.first, feedTitle: 'Testpodcast'));
      await tester.pumpAndSettle();
      expect(find.text('Eerste aflevering'), findsWidgets);

      await tester.tap(find.byTooltip('Pauze'));
      await tester.pump();
      expect(engine.playing, isFalse);

      await tester.tap(find.text('Testpodcast').last);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Stoppen'));
      await tester.pumpAndSettle();
      expect(state.current, isNull);
      expect(engine.stops, 1);
    });

    testWidgets('speler-scherm: tijd, terug/vooruit, snelheid, schuifbalk', (tester) async {
      final state = await _state();
      await state.play(MediaItem.fromEpisode(state.episodesFor(_feedUrl)!.first, feedTitle: 'Testpodcast'));
      await tester.pumpWidget(MediaspelerApp(state: state));
      await tester.pump();
      tester.state<NavigatorState>(find.byType(Navigator).first)
          .push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
      await tester.pumpAndSettle();

      engine.setPosition(const Duration(minutes: 2));
      await tester.pump();
      expect(find.text('02:00'), findsOneWidget);
      expect(find.text('1:00:00'), findsOneWidget);

      await tester.tap(find.byTooltip('30 s vooruit'));
      expect(engine.seeks.last, const Duration(minutes: 2, seconds: 30));
      await tester.tap(find.byTooltip('10 s terug'));
      expect(engine.seeks.last, const Duration(minutes: 2, seconds: 20));

      await tester.ensureVisible(find.text('1.5x'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.5x'));
      await tester.pump();
      expect(engine.rate, 1.5);

      await tester.drag(find.byType(Slider), const Offset(-1000, 0));
      expect(engine.seeks.last, Duration.zero);

      await tester.tap(find.byTooltip('Pauze'));
      await tester.pump();
      expect(engine.playing, isFalse);
    });

    testWidgets('speler-scherm zonder item', (tester) async {
      await tester.pumpWidget(MediaspelerApp(state: await _state()));
      tester.state<NavigatorState>(find.byType(Navigator).first)
          .push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Er speelt niets.'), findsOneWidget);
    });
  });

  group('overige schermen', () {
    testWidgets('op apparaat: lijst, afspelen en wegvegen', (tester) async {
      final state = await _state(localVideos: [
        {'uri': 'C:/film.mp4', 'name': 'film.mp4', 'added': DateTime(2024, 3, 7).toIso8601String()},
      ]);
      await state.storage.savePosition('local:C:/film.mp4', const Duration(minutes: 3));
      await tester.pumpWidget(MediaspelerApp(state: state));
      await tester.tap(find.text('Op apparaat'));
      await tester.pumpAndSettle();
      expect(find.text('film.mp4'), findsOneWidget);
      expect(find.text('Verder vanaf 03:00'), findsOneWidget);

      await tester.tap(find.text('film.mp4'));
      await tester.pumpAndSettle();
      expect(engine.opened.single, ('C:/film.mp4', const Duration(minutes: 3)));
      expect(find.byType(PlayerScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Dismissible), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(state.localVideos, isEmpty);
    });

    testWidgets('feed verwijderen vraagt eerst om bevestiging', (tester) async {
      final state = await _state();
      await tester.pumpWidget(MediaspelerApp(state: state));
      await tester.tap(find.text('Feeds').last);
      await tester.pumpAndSettle();
      expect(find.text('YouTube · alleen audio'), findsOneWidget);

      await tester.tap(find.byTooltip('Verwijderen').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();
      expect(state.feeds, hasLength(2));

      await tester.tap(find.byTooltip('Verwijderen').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Verwijderen'));
      await tester.pumpAndSettle();
      expect(state.feeds.map((f) => f.title), ['Testkanaal']);
    });

    testWidgets('Nieuw: filters en kopjes', (tester) async {
      final state = await _state();
      await tester.pumpWidget(MediaspelerApp(state: state));
      await tester.pumpAndSettle();
      expect(find.text('Vandaag'), findsOneWidget);
      expect(find.text('Eerste aflevering'), findsOneWidget);
      expect(find.text('YouTube-video'), findsOneWidget);

      await tester.tap(find.text("Video's"));
      await tester.pumpAndSettle();
      expect(find.text('Video-aflevering'), findsOneWidget);
      expect(find.text('Eerste aflevering'), findsNothing);
      expect(find.text('YouTube-video'), findsNothing, reason: 'kanaal staat op alleen audio');

      await tester.tap(find.text('Podcasts'));
      await tester.pumpAndSettle();
      await state.toggleFinished('p1');
      await tester.tap(find.text('Verberg beluisterd'));
      await tester.pumpAndSettle();
      expect(find.text('Eerste aflevering'), findsNothing);
      expect(find.text('YouTube-video'), findsOneWidget);
    });
  });

  group('toevoegen-dialoog', () {
    /// App zonder feeds, met een nep-internet voor het herkennen van links.
    Future<AppState> withWeb(Map<String, http.Response> routes) async {
      SharedPreferences.setMockInitialValues({});
      engine = FakeEngine();
      final client = MockClient((req) async {
        final key = '${req.url.host}${req.url.path}';
        return routes[key] ?? http.Response('weg', 404);
      });
      return AppState(await Storage.open(),
          rss: RssService(client),
          youtube: FakeYouTube(),
          podcasts: PodcastDirectory(client),
          engine: () => engine);
    }

    http.Response json(Object o) => http.Response.bytes(utf8.encode(jsonEncode(o)), 200,
        headers: {'content-type': 'application/json'});
    http.Response html(String s) => http.Response.bytes(utf8.encode(s), 200,
        headers: {'content-type': 'text/html; charset=utf-8'});
    http.Response feed() => http.Response.bytes(
        utf8.encode('<rss><channel><title>Gevonden Podcast</title><item><title>Afl</title>'
            '<guid>g1</guid><enclosure url="https://pod.example/g1.mp3" type="audio/mpeg"/>'
            '</item></channel></rss>'),
        200,
        headers: {'content-type': 'application/rss+xml'});

    Future<void> open(WidgetTester tester, AppState state, String input) async {
      await tester.pumpWidget(MediaspelerApp(state: state));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Feed toevoegen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), input);
      await tester.pump();
    }

    testWidgets('zoeken op naam, kiezen en de feed openen', (tester) async {
      final state = await withWeb({
        'itunes.apple.com/search': json({
          'results': [
            {'collectionName': 'Gevonden Podcast', 'artistName': 'Maker', 'feedUrl': 'https://pod.example/feed'}
          ]
        }),
        'pod.example/feed': feed(),
      });
      await open(tester, state, 'gevonden podcast');
      expect(find.text('Zoeken'), findsOneWidget, reason: 'naam = zoeken');
      await tester.tap(find.text('Zoeken'));
      await tester.pumpAndSettle();
      expect(find.text('Kies een podcast:'), findsOneWidget);
      await tester.tap(find.text('Gevonden Podcast'));
      await tester.pumpAndSettle();
      expect(state.feeds.single.url, 'https://pod.example/feed');
      expect(find.byType(FeedDetailScreen), findsOneWidget);
    });

    testWidgets('alleen op Spotify: uitleg en Open in Spotify', (tester) async {
      final state = await withWeb({
        'open.spotify.com/show/excl': html('<meta property="og:title" content="Exclusief"/>'
            '<meta property="og:url" content="https://open.spotify.com/show/excl"/>'),
        'itunes.apple.com/search': json({'results': <Object>[]}),
      });
      await open(tester, state, 'https://open.spotify.com/show/excl');
      await tester.tap(find.text('Toevoegen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('alleen op Spotify'), findsOneWidget);
      expect(find.text('Open in Spotify'), findsOneWidget);
      expect(state.feeds, isEmpty);
    });

    testWidgets('los mp3-bestand: direct afspelen', (tester) async {
      final state = await withWeb({});
      await open(tester, state, 'https://cdn.example/los.mp3');
      await tester.tap(find.text('Toevoegen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('kan direct in deze app afspelen'), findsOneWidget);
      await tester.tap(find.text('Nu afspelen'));
      await tester.pumpAndSettle();
      expect(engine.opened.single.$1, 'https://cdn.example/los.mp3');
      expect(state.feeds, isEmpty);
    });

    testWidgets('Apple-link naar een aflevering: toevoegen en die aflevering spelen',
        (tester) async {
      final state = await withWeb({
        'itunes.apple.com/lookup': json({
          'results': [
            {'collectionName': 'Gevonden Podcast', 'artistName': 'Maker', 'feedUrl': 'https://pod.example/feed',
              'wrapperType': 'podcastEpisode', 'kind': 'podcast-episode', 'trackName': 'Afl'}
          ]
        }),
        'pod.example/feed': feed(),
      });
      await open(tester, state, 'https://podcasts.apple.com/nl/podcast/x/id123?i=456');
      await tester.tap(find.text('Toevoegen'));
      await tester.pumpAndSettle();
      expect(state.feeds.single.title, 'Gevonden Podcast');
      expect(engine.opened.single.$1, 'https://pod.example/g1.mp3');
      expect(find.textContaining('toegevoegd'), findsOneWidget);
    });
  });

  group('feed-detail: fouten en podcastversie', () {
    testWidgets('ophalen mislukt zonder bewaarde afleveringen: foutmelding en opnieuw',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'feeds': jsonEncode([
          {'url': 'https://kapot.example/rss', 'title': 'Kapot'}
        ]),
      });
      engine = FakeEngine();
      final state = AppState(await Storage.open(),
          rss: RssService(MockClient((_) async => http.Response('', 500))),
          youtube: FakeYouTube(),
          engine: () => engine);
      await _openFeed(tester, state, 'https://kapot.example/rss');
      expect(find.textContaining('HTTP 500'), findsOneWidget);
      await tester.tap(find.text('Opnieuw proberen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('HTTP 500'), findsOneWidget);
    });

    testWidgets('YouTube-kanaal: podcastversie gevonden, voorstel tonen', (tester) async {
      final state = await _state();
      (state.podcasts as FakePodcasts).match = const PodcastMatch(
          title: 'Kanaal Podcast', author: 'Maker', feedUrl: 'https://andere.example/rss');
      await _openFeed(tester, state, _ytUrl);
      await tester.tap(find.byTooltip('Podcastversie zoeken'));
      await tester.pumpAndSettle();
      expect(find.text('Als podcast volgen?'), findsOneWidget);
      expect(find.text('Kanaal Podcast'), findsOneWidget);
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();
      expect(state.feeds, hasLength(2));
    });

    testWidgets('YouTube-kanaal zonder podcastversie: melding', (tester) async {
      final state = await _state();
      await _openFeed(tester, state, _ytUrl);
      await tester.tap(find.byTooltip('Podcastversie zoeken'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Geen podcastversie'), findsOneWidget);
    });
  });
}
