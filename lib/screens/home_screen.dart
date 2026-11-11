import 'package:flutter/material.dart';

import '../widgets/mini_player.dart';
import '../services/app_state.dart';
import 'feeds_screen.dart';
import 'latest_screen.dart';
import 'local_videos_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Met feeds: openen op "Nieuw"; zonder feeds: op "Feeds" om er een toe te voegen.
  late int _tab = AppScope.read(context).feeds.isEmpty ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const [LatestScreen(), FeedsScreen(), LocalVideosScreen()],
            ),
          ),
          const MiniPlayer(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.new_releases_outlined),
              selectedIcon: Icon(Icons.new_releases),
              label: 'Nieuw'),
          NavigationDestination(
              icon: Icon(Icons.rss_feed_outlined),
              selectedIcon: Icon(Icons.rss_feed),
              label: 'Feeds'),
          NavigationDestination(
              icon: Icon(Icons.video_library_outlined),
              selectedIcon: Icon(Icons.video_library),
              label: 'Op apparaat'),
        ],
      ),
    );
  }
}
