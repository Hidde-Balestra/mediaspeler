import 'package:audio_service/audio_service.dart' as svc;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaspeler/models.dart';
import 'package:mediaspeler/services/media_session.dart';

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
}
