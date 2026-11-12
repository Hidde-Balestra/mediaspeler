import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Beeld-in-beeld (Android): de YouTube-speler blijft in een klein venster
/// spelen als je de app verlaat. Praat met MainActivity.kt.
class PipController extends ChangeNotifier {
  static const _channel = MethodChannel('mediaspeler/pip');
  static final PipController instance = PipController._();

  PipController._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') setInPip(call.arguments == true);
    });
  }

  bool _inPip = false;

  /// Of de app nu als klein venster draait (dan alleen de video tonen).
  bool get inPip => _inPip;

  @visibleForTesting
  void setInPip(bool value) {
    if (value == _inPip) return;
    _inPip = value;
    notifyListeners();
  }

  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false; // Windows, iOS, tests
    } on PlatformException {
      return false;
    }
  }

  /// Automatisch naar beeld-in-beeld als je de app verlaat (aan op het YouTube-scherm).
  Future<void> setAuto(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setAuto', enabled);
    } on MissingPluginException {
      // Niet ondersteund op dit platform.
    } on PlatformException {
      // Idem.
    }
  }

  /// Nu meteen naar beeld-in-beeld. Geeft false als dat niet kan.
  Future<bool> enter() async {
    try {
      return await _channel.invokeMethod<bool>('enter') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
