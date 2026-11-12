import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Gebeurtenissen van de speler (zelfde vorm als `Player.stream` van media_kit).
abstract class EngineStreams {
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get playing;
  Stream<bool> get buffering;
  Stream<bool> get completed;
  Stream<double> get rate;
  Stream<String> get error;
}

/// Huidige toestand van de speler (zelfde vorm als `Player.state` van media_kit).
abstract class EngineState {
  Duration get position;
  Duration get duration;
  Duration get buffer;
  bool get playing;
  bool get buffering;
  bool get completed;
  double get rate;
}

/// Dunne laag tussen de app en de mediaspeler. In de app is dat media_kit;
/// in tests een nepspeler, zodat alle afspeellogica zonder native code te testen is.
abstract class MediaEngine {
  EngineStreams get stream;
  EngineState get state;

  Future<void> open(String uri, {Duration? start});
  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> stop();
  Future<void> dispose();

  /// Voor het videobeeld; null bij spelers zonder beeld (tests).
  VideoController? createVideoController() => null;
}

/// De echte speler: media_kit (libmpv).
class MediaKitEngine extends MediaEngine {
  final Player _player = Player();

  @override
  late final EngineStreams stream = _KitStreams(_player.stream);
  @override
  late final EngineState state = _KitState(_player);

  @override
  Future<void> open(String uri, {Duration? start}) => _player.open(Media(uri, start: start));
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> playOrPause() => _player.playOrPause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setRate(double rate) => _player.setRate(rate);
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> dispose() => _player.dispose();
  @override
  VideoController createVideoController() => VideoController(_player);
}

class _KitStreams implements EngineStreams {
  final PlayerStream _s;
  _KitStreams(this._s);
  @override
  Stream<Duration> get position => _s.position;
  @override
  Stream<Duration> get duration => _s.duration;
  @override
  Stream<bool> get playing => _s.playing;
  @override
  Stream<bool> get buffering => _s.buffering;
  @override
  Stream<bool> get completed => _s.completed;
  @override
  Stream<double> get rate => _s.rate;
  @override
  Stream<String> get error => _s.error;
}

class _KitState implements EngineState {
  final Player _p;
  _KitState(this._p);
  @override
  Duration get position => _p.state.position;
  @override
  Duration get duration => _p.state.duration;
  @override
  Duration get buffer => _p.state.buffer;
  @override
  bool get playing => _p.state.playing;
  @override
  bool get buffering => _p.state.buffering;
  @override
  bool get completed => _p.state.completed;
  @override
  double get rate => _p.state.rate;
}
