import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mediaspeler/models.dart';
import 'package:mediaspeler/services/app_state.dart';
import 'package:mediaspeler/services/rss_service.dart';
import 'package:mediaspeler/services/podcast_directory.dart';
import 'package:mediaspeler/services/storage.dart';
import 'package:mediaspeler/services/youtube_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const _feedXml = '''<?xml version="1.0"?>
<rss version="2.0"><channel>
  <title>Testfeed</title>
  <item>
    <title>Aflevering</title><guid>ep1</guid>
    <enclosure url="https://example.com/ep1.mp3" type="audio/mpeg"/>
  </item>
</channel></rss>''';

void main() {
  late List<Uri> requested;
  late FakeYouTube youtube;
  late FakePodcasts podcasts;

  Future<AppState> makeState({Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    requested = [];
    youtube = FakeYouTube();
    podcasts = FakePodcasts();
    final client = MockClient((req) async {
      requested.add(req.url);
      if (req.url.host == 'kapot.nl') return http.Response('weg', 404);
      return http.Response(_feedXml, 200);
    });
    return AppState(await Storage.open(), rss: RssService(client), youtube: youtube, podcasts: podcasts);
  }

  group('feeds', () {
    test('addFeed vult https:// aan, haalt op en bewaart', () async {
      final state = await makeState();
      final feed = await state.addFeed('  example.com/rss  ');

      expect(requested.single.toString(), 'https://example.com/rss');
      expect(feed.title, 'Testfeed');
      expect(state.feeds.single.url, 'https://example.com/rss');
      expect(state.episodesFor(feed.url), hasLength(1));
      expect(state.storage.loadFeeds().single.title, 'Testfeed');
    });

    test('dubbele feed wordt geweigerd', () async {
      final state = await makeState();
      await state.addFeed('https://example.com/rss');
      expect(() => state.addFeed('https://example.com/rss'), throwsException);
      expect(state.feeds, hasLength(1));
    });

    test('mislukte feed wordt niet toegevoegd', () async {
      final state = await makeState();
      await expectLater(state.addFeed('https://kapot.nl/rss'), throwsException);
      expect(state.feeds, isEmpty);
    });

    test('removeFeed haalt feed en afleveringen weg', () async {
      final state = await makeState();
      final feed = await state.addFeed('https://example.com/rss');
      await state.removeFeed(feed);
      expect(state.feeds, isEmpty);
      expect(state.episodesFor(feed.url), isNull);
      expect(state.storage.loadFeeds(), isEmpty);
    });

    test('refreshFeed werkt titel bij en zet laadstatus terug', () async {
      final state = await makeState();
      const old = Feed(url: 'https://example.com/rss', title: 'Oude titel');
      await state.storage.saveFeeds(const [old]);
      final fresh = AppState(state.storage, rss: state.rss);

      final future = fresh.refreshFeed(old);
      expect(fresh.isLoading(old.url), isTrue);
      await future;
      expect(fresh.isLoading(old.url), isFalse);
      expect(fresh.feeds.single.title, 'Testfeed');
      expect(fresh.feeds.single.lastFetched, isNotNull);
    });

    test('refreshFeed geeft fout door en stopt met laden', () async {
      final state = await makeState();
      const feed = Feed(url: 'https://kapot.nl/rss', title: 'X');
      await expectLater(state.refreshFeed(feed), throwsException);
      expect(state.isLoading(feed.url), isFalse);
    });
  });

  test('toggleFinished markeert en wist de positie', () async {
    final state = await makeState();
    await state.storage.savePosition('ep1', const Duration(minutes: 3));

    await state.toggleFinished('ep1');
    expect(state.finished, contains('ep1'));
    expect(state.savedPosition('ep1'), isNull);

    await state.toggleFinished('ep1');
    expect(state.finished, isNot(contains('ep1')));
  });

  group('lokale video\'s', () {
    test('toevoegen zonder dubbelen', () async {
      final state = await makeState();
      final a = LocalVideo(uri: 'a', name: 'A', added: DateTime(2024));
      final b = LocalVideo(uri: 'b', name: 'B', added: DateTime(2024));
      await state.addLocalVideos([a]);
      await state.addLocalVideos([a, b]);
      expect(state.localVideos.map((v) => v.uri), ['a', 'b']);
      expect(state.storage.loadLocalVideos(), hasLength(2));
    });

    test('verwijderen wist ook de positie', () async {
      final state = await makeState();
      final a = LocalVideo(uri: 'a', name: 'A', added: DateTime(2024));
      await state.addLocalVideos([a]);
      await state.storage.savePosition('local:a', const Duration(seconds: 30));
      await state.removeLocalVideo(a);
      expect(state.localVideos, isEmpty);
      expect(state.savedPosition('local:a'), isNull);
    });
  });

  group('thema', () {
    test('standaard volgt het systeem', () async {
      expect((await makeState()).themeMode, ThemeMode.system);
    });

    test('bewaarde voorkeur wordt geladen', () async {
      final state = await makeState(prefs: {'theme_mode': 'dark'});
      expect(state.themeMode, ThemeMode.dark);
    });

    test('onbekende waarde valt terug op systeem', () async {
      final state = await makeState(prefs: {'theme_mode': 'paars'});
      expect(state.themeMode, ThemeMode.system);
    });

    test('setThemeMode meldt de wijziging en bewaart hem', () async {
      final state = await makeState();
      var notified = 0;
      state.addListener(() => notified++);
      await state.setThemeMode(ThemeMode.light);
      expect(state.themeMode, ThemeMode.light);
      expect(notified, 1);
      expect(state.storage.themeMode(), 'light');
    });
  });

  test('stop zonder speler doet niets mis', () async {
    final state = await makeState();
    await state.stop();
    expect(state.current, isNull);
  });

  group('YouTube', () {
    test('kanaal toevoegen via @handle met alleen-audio', () async {
      final state = await makeState();
      final feed = await state.addFeed('@kanaal', audioOnly: true);

      expect(youtube.resolved, ['@kanaal']);
      expect(requested.single.toString(),
          'https://www.youtube.com/feeds/videos.xml?channel_id=UCtest');
      expect(feed.url, 'https://www.youtube.com/feeds/videos.xml?channel_id=UCtest');
      expect(feed.audioOnly, isTrue);
      expect(feed.imageUrl, 'https://yt3.example/logo.jpg',
          reason: 'YouTube-feeds hebben geen eigen afbeelding');
      expect(state.storage.loadFeeds().single.audioOnly, isTrue);
    });

    test('hetzelfde kanaal via een andere link is een dubbele', () async {
      final state = await makeState();
      await state.addFeed('@kanaal');
      expect(() => state.addFeed('https://www.youtube.com/@kanaal'), throwsException);
    });

    test('gewone feeds gaan niet langs YouTube', () async {
      final state = await makeState();
      await state.addFeed('https://example.com/rss', audioOnly: true);
      expect(youtube.resolved, isEmpty);
    });

    test('setAudioOnly wijzigt en bewaart de keuze', () async {
      final state = await makeState();
      final feed = await state.addFeed('@kanaal');
      expect(feed.audioOnly, isFalse);
      await state.setAudioOnly(feed, true);
      expect(state.feedByUrl(feed.url)!.audioOnly, isTrue);
      expect(state.storage.loadFeeds().single.audioOnly, isTrue);
    });

    test('mislukte stream: foutmelding en niets blijft hangen als "speelt nu"', () async {
      final state = await makeState();
      youtube.streamError = const YouTubeException('geblokkeerd');
      const item = MediaItem(
        id: 'yt:video:dQw4w9WgXcQ',
        title: 'Video',
        uri: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        kind: MediaKind.audio,
        youtubeId: 'dQw4w9WgXcQ',
      );
      await expectLater(state.play(item), throwsA(isA<YouTubeException>()));
      expect(youtube.streams.single, ('dQw4w9WgXcQ', true), reason: 'audio-only gevraagd');
      expect(state.current, isNull);
    });
  });

  group('podcastversie zoeken', () {
    const match = PodcastMatch(
        title: 'Kanaal Podcast', author: 'Kanaal', feedUrl: 'https://pod.example/feed');

    test('zoekt op de kanaalnaam', () async {
      final state = await makeState();
      podcasts.match = match;
      final found = await state.findPodcastVersion('@kanaal');
      expect(podcasts.searched, ['Kanaal']);
      expect(found!.feedUrl, 'https://pod.example/feed');
    });

    test('geen resultaat als je de podcast al volgt', () async {
      final state = await makeState();
      podcasts.match = match;
      await state.addFeed('https://pod.example/feed');
      expect(await state.findPodcastVersion('@kanaal'), isNull);
    });

    test('fout bij zoeken betekent gewoon: niet gevonden', () async {
      final state = await makeState();
      youtube.resolveError = Exception('netwerk weg');
      expect(await state.findPodcastVersion('@kanaal'), isNull);
    });

    test('voor een bestaand YouTube-kanaal', () async {
      final state = await makeState();
      podcasts.match = match;
      final feed = await state.addFeed('@kanaal');
      expect((await state.findPodcastVersionFor(feed))!.title, 'Kanaal Podcast');
      expect(podcasts.searched.last, feed.title);
    });
  });

  group('alle afleveringen (Nieuw)', () {
    Future<AppState> withTwoFeeds() async {
      SharedPreferences.setMockInitialValues({});
      final client = MockClient((req) async => http.Response(
          req.url.host == 'a.example'
              ? '''<rss><channel><title>A</title>
                  <item><title>A-oud</title><guid>a1</guid><pubDate>Mon, 01 Jan 2024 10:00:00 GMT</pubDate>
                    <enclosure url="https://a.example/1.mp3" type="audio/mpeg"/></item>
                  <item><title>A-zonder-datum</title><guid>a2</guid>
                    <enclosure url="https://a.example/2.mp3" type="audio/mpeg"/></item>
                </channel></rss>'''
              : '''<rss><channel><title>B</title>
                  <item><title>B-nieuw</title><guid>b1</guid><pubDate>Wed, 03 Jan 2024 10:00:00 GMT</pubDate>
                    <enclosure url="https://b.example/1.mp4" type="video/mp4"/></item>
                  <item><title>B-midden</title><guid>b2</guid><pubDate>Tue, 02 Jan 2024 10:00:00 GMT</pubDate>
                    <enclosure url="https://b.example/2.mp3" type="audio/mpeg"/></item>
                </channel></rss>''',
          200));
      final state = AppState(await Storage.open(),
          rss: RssService(client), youtube: FakeYouTube(), podcasts: FakePodcasts());
      await state.addFeed('https://a.example/rss');
      await state.addFeed('https://b.example/rss');
      return state;
    }

    test('nieuwste eerst, zonder datum achteraan', () async {
      final state = await withTwoFeeds();
      expect(state.allEpisodes().map((e) => e.$1.title),
          ['B-nieuw', 'B-midden', 'A-oud', 'A-zonder-datum']);
      expect(state.allEpisodes().first.$2.title, 'B');
    });

    test('filter op audio/video en verberg beluisterd', () async {
      final state = await withTwoFeeds();
      expect(state.allEpisodes(kind: MediaKind.video).map((e) => e.$1.title), ['B-nieuw']);
      await state.toggleFinished('b2');
      expect(state.allEpisodes(kind: MediaKind.audio, hideFinished: true).map((e) => e.$1.title),
          ['A-oud', 'A-zonder-datum']);
    });

    test('afleveringen worden bewaard en na herstart direct getoond', () async {
      final state = await withTwoFeeds();
      final again = AppState(state.storage, rss: state.rss, youtube: FakeYouTube());
      expect(again.allEpisodes(), hasLength(4));
    });

    test('refreshAll vernieuwt alles en telt mislukte feeds', () async {
      final state = await withTwoFeeds();
      await state.storage.saveFeeds([...state.feeds, const Feed(url: 'https://kapot.nl/rss', title: 'X')]);
      final again = AppState(state.storage,
          rss: RssService(MockClient((req) async => req.url.host == 'kapot.nl'
              ? http.Response('', 500)
              : http.Response('<rss><channel><title>Z</title></channel></rss>', 200))),
          youtube: FakeYouTube());
      expect(await again.refreshAll(), 1);
      expect(again.refreshingAll, isFalse);
    });

    test('findEpisode op titel (voor links naar één aflevering)', () async {
      final state = await withTwoFeeds();
      expect(state.findEpisode('https://b.example/rss', 'b-midden')!.id, 'b2');
      expect(state.findEpisode('https://b.example/rss', 'Heel iets anders'), isNull);
    });
  });

  test('feed verwijderd tijdens vernieuwen: afleveringen niet alsnog bewaard', () async {
    final state = await makeState();
    final feed = await state.addFeed('https://example.com/rss');
    final refreshing = state.refreshFeed(feed);
    await state.removeFeed(feed);
    await refreshing;
    expect(state.episodesFor(feed.url), isNull);
    expect(state.storage.loadEpisodes(feed.url), isEmpty);
    expect(state.isLoading(feed.url), isFalse);
  });
}
