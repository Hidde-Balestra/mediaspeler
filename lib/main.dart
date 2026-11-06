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

class MediaspelerApp extends StatelessWidget {
  final AppState state;
  const MediaspelerApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF6750A4);
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Mediaspeler',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
        darkTheme: ThemeData(
            colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
        home: const HomeScreen(),
      ),
    );
  }
}
