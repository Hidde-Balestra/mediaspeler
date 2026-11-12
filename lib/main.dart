import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/home_screen.dart';
import 'services/app_state.dart';
import 'services/media_session.dart';
import 'services/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final storage = await Storage.open();
  final state = AppState(storage);
  await _initMediaSession(state);
  runApp(MediaspelerApp(state: state));
  // Eens per week: alle feeds vernieuwen en verlopen cache opruimen (op de achtergrond).
  unawaited(state.weeklyMaintenance().catchError((_) => false));
}

/// Achtergrond-afspelen en bediening via melding/vergrendelscherm (Android, iOS).
/// Op Windows speelt de app op de achtergrond gewoon door.
Future<void> _initMediaSession(AppState state) async {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
  try {
    await AudioService.init(
      builder: () => MediaSessionHandler(state),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'nl.hiddebalestra.mediaspeler.playback',
        androidNotificationChannelName: 'Afspelen',
        androidNotificationIcon: 'drawable/ic_launcher_monochrome',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        rewindInterval: rewindInterval,
        fastForwardInterval: fastForwardInterval,
      ),
    );
  } catch (e) {
    // De app werkt ook zonder mediasessie, alleen niet op de achtergrond.
    debugPrint('Mediasessie starten mislukt: $e');
  }
}

const _seed = Color(0xFF6750A4);

/// Licht of donker Material 3-thema op basis van dezelfde accentkleur.
ThemeData buildTheme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
      useMaterial3: true,
    );

class MediaspelerApp extends StatelessWidget {
  final AppState state;
  const MediaspelerApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: 'Mediaspeler',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: state.themeMode,
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
