import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/home_screen.dart';
import 'services/app_state.dart';
import 'services/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final storage = await Storage.open();
  runApp(MediaspelerApp(state: AppState(storage)));
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
