import 'dart:async';

import 'package:audio_service/audio_service.dart' as svc;

import '../models.dart';
import 'app_state.dart';

const rewindInterval = Duration(seconds: 10);
const fastForwardInterval = Duration(seconds: 30);

/// Zet de app-[MediaItem] om naar het formaat van audio_service
/// (titel, kanaal en cover op het vergrendelscherm en in de melding).
svc.MediaItem toSessionItem(MediaItem item, {Duration? duration}) => svc.MediaItem(
      id: item.id,
      title: item.title,
      artist: item.subtitle,
      album: item.subtitle,
      artUri: item.imageUrl != null ? Uri.tryParse(item.imageUrl!) : null,
      duration: duration != null && duration > Duration.zero ? duration : null,
      extras: {'kind': item.kind.name},
    );

/// Bouwt de afspeelstatus voor de systeem-mediasessie.
svc.PlaybackState buildPlaybackState({
  required bool playing,
  required bool buffering,
  required bool completed,
  required Duration position,
  Duration buffered = Duration.zero,
  double speed = 1.0,
}) {
  final svc.AudioProcessingState processing;
  if (completed) {
    processing = svc.AudioProcessingState.completed;
  } else if (buffering) {
    processing = svc.AudioProcessingState.buffering;
  } else {
    processing = svc.AudioProcessingState.ready;
  }
  return svc.PlaybackState(
    controls: [
      svc.MediaControl.rewind,
      playing ? svc.MediaControl.pause : svc.MediaControl.play,
      svc.MediaControl.fastForward,
      svc.MediaControl.stop,
    ],
    systemActions: const {
      svc.MediaAction.seek,
      svc.MediaAction.seekForward,
      svc.MediaAction.seekBackward,
    },
    androidCompactActionIndices: const [0, 1, 2],
    processingState: processing,
    playing: playing,
    updatePosition: position,
    bufferedPosition: buffered,
    speed: speed,
  );
}

/// Koppelt de speler uit [AppState] aan de mediasessie van het systeem, zodat
/// afspelen doorgaat op de achtergrond en bediend kan worden via de melding,
/// het vergrendelscherm en koptelefoonknoppen.
class MediaSessionHandler extends svc.BaseAudioHandler with svc.SeekHandler {
  final AppState state;
  final List<StreamSubscription> _subs = [];
  String? _currentId;

  MediaSessionHandler(this.state) {
    state.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    final item = state.current;
    if (item == null) {
      if (_currentId != null) {
        _currentId = null;
        mediaItem.add(null);
        playbackState.add(playbackState.value.copyWith(
          processingState: svc.AudioProcessingState.idle,
          playing: false,
        ));
      }
      return;
    }
    if (_subs.isEmpty) _attachPlayer();
    if (item.id != _currentId) {
      _currentId = item.id;
      mediaItem.add(toSessionItem(item));
    }
    _pushState();
  }

  void _attachPlayer() {
    final s = state.player.stream;
    _subs
      ..add(s.playing.listen((_) => _pushState()))
      ..add(s.buffering.listen((_) => _pushState()))
      ..add(s.completed.listen((_) => _pushState()))
      ..add(s.rate.listen((_) => _pushState()))
      // Na een seek de nieuwe positie doorgeven (de systeem-UI interpoleert verder zelf).
      ..add(s.position
          .where((p) => (p - playbackState.value.position).abs() > const Duration(seconds: 2))
          .listen((_) => _pushState()))
      ..add(s.duration.listen((d) {
        final item = state.current;
        if (item != null) mediaItem.add(toSessionItem(item, duration: d));
      }));
  }

  void _pushState() {
    if (state.current == null) return;
    final p = state.player.state;
    playbackState.add(buildPlaybackState(
      playing: p.playing,
      buffering: p.buffering,
      completed: p.completed,
      position: p.position,
      buffered: p.buffer,
      speed: p.rate,
    ));
  }

  @override
  Future<void> play() async {
    final item = state.current;
    if (item != null) await state.play(item);
  }

  @override
  Future<void> pause() => state.player.pause();

  @override
  Future<void> seek(Duration position) => state.player.seek(position);

  @override
  Future<void> rewind() => state.skip(-rewindInterval);

  @override
  Future<void> fastForward() => state.skip(fastForwardInterval);

  @override
  Future<void> setSpeed(double speed) => state.setRate(speed);

  @override
  Future<void> stop() async {
    await state.stop();
    await super.stop();
  }

  void dispose() {
    state.removeListener(_onStateChanged);
    for (final s in _subs) {
      s.cancel();
    }
  }
}
