import 'package:audio_service/audio_service.dart' as svc;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaspeler/models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mediaspeler/services/app_state.dart';
import 'package:mediaspeler/services/media_session.dart';
import 'package:mediaspeler/services/rss_service.dart';
import 'package:mediaspeler/services/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  group('toSessionItem', () {
    const item = MediaItem(
      id: 'ep1',
      title: 'Aflevering 1',
      subtitle: 'Testpodcast',
      uri: 'https://example.com/ep1.mp3',
      kind: MediaKind.audio,
      imageUrl: 'https://example.com/cover.jpg',
    );

    test('neemt titel, kanaal en cover over', () {
      final s = toSessionItem(item, duration: const Duration(minutes: 42));
      expect(s.id, 'ep1');
      expect(s.title, 'Aflevering 1');
      expect(s.artist, 'Testpodcast');
      expect(s.artUri, Uri.parse('https://example.com/cover.jpg'));
      expect(s.duration, const Duration(minutes: 42));
      expect(s.extras, {'kind': 'audio'});
    });

    test('lege duur en ontbrekende cover worden weggelaten', () {
      const local = MediaItem(id: 'l', title: 'Film', uri: 'C:/f.mp4', kind: MediaKind.video);
      final s = toSessionItem(local, duration: Duration.zero);
      expect(s.duration, isNull);
      expect(s.artUri, isNull);
      expect(s.extras, {'kind': 'video'});
    });
  });

  group('buildPlaybackState', () {
    test('spelend: pauzeknop en status ready', () {
      final s = buildPlaybackState(
        playing: true,
        buffering: false,
        completed: false,
        position: const Duration(seconds: 12),
        speed: 1.5,
      );
      expect(s.playing, isTrue);
      expect(s.processingState, svc.AudioProcessingState.ready);
      expect(s.controls, contains(svc.MediaControl.pause));
      expect(s.controls, isNot(contains(svc.MediaControl.play)));
      expect(s.updatePosition, const Duration(seconds: 12));
      expect(s.speed, 1.5);
      expect(s.systemActions, contains(svc.MediaAction.seek));
      expect(s.androidCompactActionIndices, [0, 1, 2]);
    });

    test('gepauzeerd: afspeelknop', () {
      final s = buildPlaybackState(
          playing: false, buffering: false, completed: false, position: Duration.zero);
      expect(s.controls, contains(svc.MediaControl.play));
    });

    test('bufferen en afgelopen', () {
      expect(
        buildPlaybackState(
                playing: true, buffering: true, completed: false, position: Duration.zero)
            .processingState,
        svc.AudioProcessingState.buffering,
      );
      expect(
        buildPlaybackState(
                playing: false, buffering: true, completed: true, position: Duration.zero)
            .processingState,
        svc.AudioProcessingState.completed,
      );
    });
  });

  group('MediaSessionHandler (vergrendelscherm, melding, koptelefoon)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    late FakeEngine engine;
    late AppState state;
    late MediaSessionHandler handler;

    const item = MediaItem(
        id: 'ep1', title: 'Aflevering', subtitle: 'Podcast',
        uri: 'https://cdn.example/ep1.mp3', kind: MediaKind.audio,
        imageUrl: 'https://img.example/c.jpg');

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      engine = FakeEngine();
      state = AppState(await Storage.open(),
          rss: RssService(MockClient((_) async => http.Response('', 500))),
          youtube: FakeYouTube(),
          engine: () => engine);
      handler = MediaSessionHandler(state);
    });

    tearDown(() => handler.dispose());

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('toont titel, podcast en cover; duur zodra die bekend is', () async {
      await state.play(item);
      await settle();
      final m = handler.mediaItem.value!;
      expect(m.title, 'Aflevering');
      expect(m.artist, 'Podcast');
      expect(m.artUri.toString(), 'https://img.example/c.jpg');
      expect(m.duration, const Duration(minutes: 60));
      expect(handler.playbackState.value.playing, isTrue);
    });

    test('pauzeknop pauzeert en de status volgt', () async {
      await state.play(item);
      await handler.pause();
      expect(engine.pauses, 1);
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.controls, contains(svc.MediaControl.play));
    });

    test('afspeelknop gaat verder zonder opnieuw te openen', () async {
      await state.play(item);
      await handler.pause();
      await handler.play();
      expect(engine.playing, isTrue);
      expect(engine.opened, hasLength(1));
    });

    test('koptelefoonknop wisselt tussen spelen en pauze', () async {
      await state.play(item);
      await handler.click();
      expect(engine.playing, isFalse);
      await handler.click();
      expect(engine.playing, isTrue);
    });

    test('terug, vooruit, zoeken en snelheid', () async {
      await state.play(item);
      await settle();
      engine.position = const Duration(minutes: 5);
      await handler.rewind();
      expect(engine.seeks.last, const Duration(minutes: 4, seconds: 50));
      engine.position = const Duration(minutes: 5);
      await handler.fastForward();
      expect(engine.seeks.last, const Duration(minutes: 5, seconds: 30));
      await handler.seek(const Duration(minutes: 20));
      expect(engine.seeks.last, const Duration(minutes: 20));
      expect(handler.playbackState.value.updatePosition, const Duration(minutes: 20));
      await handler.setSpeed(1.25);
      expect(state.rate, 1.25);
      expect(handler.playbackState.value.speed, 1.25);
    });

    test('bufferen en einde worden doorgegeven', () async {
      await state.play(item);
      engine.setBuffering(true);
      expect(handler.playbackState.value.processingState, svc.AudioProcessingState.buffering);
      engine.setBuffering(false);
      engine.finish();
      expect(handler.playbackState.value.processingState, svc.AudioProcessingState.completed);
    });

    test('stoppen haalt de bediening weg', () async {
      await state.play(item);
      await handler.stop();
      expect(state.current, isNull);
      expect(handler.mediaItem.value, isNull);
      expect(handler.playbackState.value.processingState, svc.AudioProcessingState.idle);
    });

    test('afspelen zonder item doet niets', () async {
      await handler.play();
      expect(engine.opened, isEmpty);
    });
  });
}
