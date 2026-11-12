import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mediaspeler/models.dart';
import 'package:mediaspeler/services/app_state.dart';
import 'package:mediaspeler/services/rss_service.dart';
import 'package:mediaspeler/services/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const _episode = MediaItem(
  id: 'ep1',
  title: 'Aflevering 1',
  subtitle: 'Podcast',
  uri: 'https://cdn.example/ep1.mp3',
  kind: MediaKind.audio,
);

const _yt = MediaItem(
  id: 'yt:video:dQw4w9WgXcQ',
  title: 'Video',
  uri: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
  kind: MediaKind.audio,
  youtubeId: 'dQw4w9WgXcQ',
);

late FakeEngine engine;
late FakeYouTube youtube;

Future<AppState> _state([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  engine = FakeEngine();
  youtube = FakeYouTube();
  return AppState(await Storage.open(),
      rss: RssService(MockClient((_) async => http.Response('', 500))),
      youtube: youtube,
      podcasts: FakePodcasts(),
      engine: () => engine);
}

/// Laat microtaken (zoals de duur die de nepspeler meldt) afhandelen.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('afspelen', () {
    test('opent de URL, zet de snelheid en onthoudt het als laatst gespeeld', () async {
      final state = await _state();
      await state.setRate(1.5);
      await state.play(_episode);
      expect(engine.opened.single, ('https://cdn.example/ep1.mp3', null));
      expect(engine.rate, 1.5);
      expect(state.current, _episode);
      expect(state.storage.lastPlayed()!.id, 'ep1');
      expect(state.lastPlayed, isNull, reason: 'er speelt nu iets');
    });

    test('hetzelfde item nog eens: alleen verder spelen, niet opnieuw openen', () async {
      final state = await _state();
      await state.play(_episode);
      await engine.pause();
      await state.play(_episode);
      expect(engine.opened, hasLength(1));
      expect(engine.playing, isTrue);
    });

    test('zelfde item als video: opnieuw openen', () async {
      final state = await _state();
      await state.play(_yt);
      await state.play(MediaItem(
          id: _yt.id, title: _yt.title, uri: _yt.uri, kind: MediaKind.video, youtubeId: _yt.youtubeId));
      expect(youtube.streams, [('dQw4w9WgXcQ', true), ('dQw4w9WgXcQ', false)]);
      expect(engine.opened, hasLength(2));
    });

    test('YouTube: stream-URL van de service, met alleen audio', () async {
      final state = await _state();
      await state.play(_yt);
      expect(youtube.streams.single, ('dQw4w9WgXcQ', true));
      expect(engine.opened.single.$1, 'https://stream.example/dQw4w9WgXcQ');
    });

    test('mislukte YouTube-stream: vorige item blijft spelen', () async {
      final state = await _state();
      await state.play(_episode);
      youtube.streamError = Exception('geblokkeerd');
      await expectLater(state.play(_yt), throwsException);
      expect(state.current, _episode);
      expect(engine.opened, hasLength(1));
    });
  });

  group('verder waar je was', () {
    test('begint op de bewaarde positie', () async {
      final state = await _state({'pos:ep1': 100000});
      await state.play(_episode);
      expect(engine.opened.single.$2, const Duration(seconds: 100));
    });

    test('speler negeert de start: er wordt alsnog naar de plek gespoeld', () async {
      final state = await _state({'pos:ep1': 100000});
      engine.honoursStart = false;
      await state.play(_episode);
      await _settle();
      expect(engine.seeks, [const Duration(seconds: 100)]);
      expect(state.savedPosition('ep1'), const Duration(seconds: 100));
    });

    test('0:00 tijdens het laden overschrijft de bewaarde plek niet', () async {
      final state = await _state({'pos:ep1': 100000});
      engine.honoursStart = false;
      engine.durationOnOpen = Duration.zero; // duur komt (nog) niet
      final playing = state.play(_episode);
      engine.setPosition(const Duration(seconds: 1));
      await engine.pause(); // pauze-event probeert ook te bewaren
      expect(state.savedPosition('ep1'), const Duration(seconds: 100));
      for (var i = 0; i < 5; i++) {
        await _settle(); // speler wacht nu op de duur
      }
      engine.setDuration(const Duration(minutes: 60));
      await playing;
    });

    test('positie wordt tijdens het spelen bewaard', () async {
      final state = await _state();
      await state.play(_episode);
      engine.setPosition(const Duration(seconds: 42));
      expect(state.savedPosition('ep1'), const Duration(seconds: 42));
    });

    test('de eerste 5 seconden worden niet bewaard', () async {
      final state = await _state();
      await state.play(_episode);
      engine.setPosition(const Duration(seconds: 3));
      expect(state.savedPosition('ep1'), isNull);
    });

    test('bij pauzeren wordt meteen bewaard', () async {
      final state = await _state();
      await state.play(_episode);
      engine.setPosition(const Duration(seconds: 30)); // eerste keer: bewaard
      engine.position = const Duration(seconds: 33); // binnen 5 s: niet via de stream
      await engine.pause();
      expect(state.savedPosition('ep1'), const Duration(seconds: 33));
    });

    test('naar een ander item: positie van het vorige wordt bewaard', () async {
      final state = await _state();
      await state.play(_episode);
      engine.position = const Duration(minutes: 7);
      await state.play(_yt);
      expect(state.savedPosition('ep1'), const Duration(minutes: 7));
    });

    test('afgelopen: beluisterd, positie en "verder luisteren" gewist', () async {
      final state = await _state();
      await state.play(_episode);
      engine.setPosition(const Duration(minutes: 10));
      engine.finish();
      await _settle();
      expect(state.finished, contains('ep1'));
      expect(state.savedPosition('ep1'), isNull);
      expect(state.storage.lastPlayed(), isNull);
    });

    test('stoppen: positie bewaard, niets meer "nu bezig"', () async {
      final state = await _state();
      await state.play(_episode);
      engine.position = const Duration(minutes: 3);
      await state.stop();
      expect(engine.stops, 1);
      expect(state.current, isNull);
      expect(state.savedPosition('ep1'), const Duration(minutes: 3));
      expect(state.storage.lastPlayed(), isNull);
    });

    test('na herstart: laatst gespeeld beschikbaar en te vergeten', () async {
      final state = await _state();
      await state.play(_episode);
      final again = AppState(state.storage, engine: FakeEngine.new);
      expect(again.lastPlayed!.id, 'ep1');
      await again.forgetLastPlayed();
      expect(again.lastPlayed, isNull);
    });
  });

  group('herstel van een verlopen YouTube-stream', () {
    Future<void> waitRecover() async {
      for (var i = 0; i < 5; i++) {
        await _settle();
      }
    }

    test('afspelen staat stil na een fout: nieuwe stream, zelfde plek', () async {
      final state = await _state();
      state.recoverCheckDelay = Duration.zero;
      await state.play(_yt);
      engine.setPosition(const Duration(minutes: 12));
      engine.fail('HTTP 403');
      await waitRecover();
      expect(youtube.invalidated, ['dQw4w9WgXcQ']);
      expect(youtube.streams, hasLength(2));
      expect(engine.opened.last.$2, const Duration(minutes: 12));
    });

    test('onschuldige fout terwijl het gewoon doorspeelt: niets doen', () async {
      final state = await _state();
      state.recoverCheckDelay = const Duration(milliseconds: 20);
      await state.play(_yt);
      engine.setPosition(const Duration(minutes: 12));
      engine.fail('waarschuwing');
      engine.setPosition(const Duration(minutes: 12, seconds: 2)); // speelt door
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(youtube.streams, hasLength(1));
      expect(engine.opened, hasLength(1));
    });

    test('maximaal 3 keer per video (geen eindeloze lus)', () async {
      final state = await _state();
      state.recoverCheckDelay = Duration.zero;
      await state.play(_yt);
      for (var i = 0; i < 6; i++) {
        engine.fail('HTTP 403');
        await waitRecover();
      }
      expect(youtube.streams, hasLength(1 + AppState.maxRecoveries));
    });

    test('fout bij een gewone podcast: niets opnieuw ophalen', () async {
      final state = await _state();
      state.recoverCheckDelay = Duration.zero;
      await state.play(_episode);
      engine.fail('netwerk');
      await waitRecover();
      expect(engine.opened, hasLength(1));
      expect(youtube.streams, isEmpty);
    });
  });

  group('bediening', () {
    test('skip blijft binnen begin en einde', () async {
      final state = await _state();
      await state.play(_episode);
      await _settle();
      engine.position = const Duration(seconds: 5);
      await state.skip(const Duration(seconds: -10));
      expect(engine.seeks.last, Duration.zero);
      engine.position = const Duration(minutes: 59, seconds: 50);
      await state.skip(const Duration(seconds: 30));
      expect(engine.seeks.last, const Duration(minutes: 60));
      engine.position = const Duration(minutes: 1);
      await state.skip(const Duration(seconds: 30));
      expect(engine.seeks.last, const Duration(minutes: 1, seconds: 30));
    });

    test('snelheid wordt doorgegeven en gemeld', () async {
      final state = await _state();
      var notified = 0;
      state.addListener(() => notified++);
      await state.setRate(2.0);
      expect(engine.rate, 2.0);
      expect(state.rate, 2.0);
      expect(notified, greaterThan(0));
    });

    test('opruimen sluit de speler', () async {
      final state = await _state();
      await state.play(_episode);
      state.dispose();
      expect(engine.disposed, isTrue);
    });
  });
}
