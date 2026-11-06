import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mediaspeler/models.dart';
import 'package:mediaspeler/services/app_state.dart';
import 'package:mediaspeler/services/rss_service.dart';
import 'package:mediaspeler/services/storage.dart';
import 'package:mediaspeler/services/youtube_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _feedXml = '''<?xml version="1.0"?>
<rss version="2.0"><channel>
  <title>Testfeed</title>
  <item>
    <title>Aflevering</title><guid>ep1</guid>
    <enclosure url="https://example.com/ep1.mp3" type="audio/mpeg"/>
  </item>
</channel></rss>''';

/// Nep-YouTube: geen netwerk, wel bijhouden wat er gevraagd wordt.
class FakeYouTube extends YouTubeService {
  final List<String> resolved = [];
  final List<(String, bool)> streams = [];
  Object? streamError;

  @override
  Future<YouTubeFeedRef> resolveFeed(String input) async {
    resolved.add(input);
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

void main() {
  late List<Uri> requested;
  late FakeYouTube youtube;

  Future<AppState> makeState({Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    requested = [];
    youtube = FakeYouTube();
    final client = MockClient((req) async {
      requested.add(req.url);
      if (req.url.host == 'kapot.nl') return http.Response('weg', 404);
      return http.Response(_feedXml, 200);
    });
    return AppState(await Storage.open(), rss: RssService(client), youtube: youtube);
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
}
