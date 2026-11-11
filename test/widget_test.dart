import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mediaspeler/main.dart';
import 'package:mediaspeler/services/app_state.dart';
import 'package:mediaspeler/services/podcast_directory.dart';
import 'package:mediaspeler/services/rss_service.dart';
import 'package:mediaspeler/services/storage.dart';
import 'package:mediaspeler/widgets/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

Future<AppState> _state([Map<String, Object> prefs = const {}, FakePodcasts? podcasts]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final client = MockClient((_) async => http.Response('', 500));
  return AppState(await Storage.open(),
      rss: RssService(client), youtube: FakeYouTube(), podcasts: podcasts ?? FakePodcasts());
}

Brightness _brightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first)).brightness;

void main() {
  group('opmaak', () {
    test('formatDuration', () {
      expect(formatDuration(const Duration(seconds: 5)), '00:05');
      expect(formatDuration(const Duration(minutes: 12, seconds: 34)), '12:34');
      expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    });

    test('formatDate', () {
      expect(formatDate(DateTime(2024, 3, 7)), '07-03-2024');
    });
  });

  testWidgets('Cover toont het fallback-icoon zonder URL', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Cover(fallbackIcon: Icons.movie)));
    expect(find.byIcon(Icons.movie), findsOneWidget);
  });

  testWidgets('startscherm toont lege feedlijst en navigatie', (tester) async {
    await tester.pumpWidget(MediaspelerApp(state: await _state()));
    expect(find.text('Nog geen feeds'), findsOneWidget);
    expect(find.text('Feed toevoegen'), findsOneWidget);

    await tester.tap(find.text('Op apparaat'));
    await tester.pumpAndSettle();
    expect(find.text("Nog geen video's"), findsOneWidget);
  });

  testWidgets('bewaard donker thema wordt toegepast', (tester) async {
    await tester.pumpWidget(MediaspelerApp(state: await _state({'theme_mode': 'dark'})));
    expect(_brightness(tester), Brightness.dark);
    expect(find.byIcon(Icons.dark_mode), findsWidgets);
  });

  testWidgets('systeemthema volgt de platform-instelling', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(MediaspelerApp(state: await _state()));
    expect(_brightness(tester), Brightness.dark);
  });

  testWidgets('thema wisselen via het menu', (tester) async {
    final state = await _state();
    await tester.pumpWidget(MediaspelerApp(state: state));
    expect(_brightness(tester), Brightness.light);

    await tester.tap(find.byTooltip('Thema').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<ThemeMode>, 'Donker'));
    await tester.pumpAndSettle();

    expect(state.themeMode, ThemeMode.dark);
    expect(_brightness(tester), Brightness.dark);
    expect(state.storage.themeMode(), 'dark');
  });

  testWidgets('feed toevoegen toont een foutmelding als ophalen mislukt', (tester) async {
    await tester.pumpWidget(MediaspelerApp(state: await _state()));
    await tester.tap(find.text('Feed toevoegen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://example.com/rss');
    await tester.tap(find.text('Toevoegen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('HTTP 500'), findsOneWidget);
  });

  testWidgets('YouTube-link toont de optie "Afspelen als podcast"', (tester) async {
    await tester.pumpWidget(MediaspelerApp(state: await _state()));
    await tester.tap(find.text('Feed toevoegen'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'https://example.com/rss');
    await tester.pump();
    expect(find.text('Afspelen als podcast'), findsNothing);

    await tester.enterText(find.byType(TextField), 'youtube.com/@kanaal');
    await tester.pump();
    expect(find.text('Afspelen als podcast'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
  });

  testWidgets('YouTube-kanaal met podcastversie: voorstel en als podcast toevoegen',
      (tester) async {
    final podcasts = FakePodcasts(const PodcastMatch(
        title: 'Kanaal Podcast', author: 'Kanaal', feedUrl: 'https://pod.example/feed'));
    // Elke feed "bestaat" in deze test.
    SharedPreferences.setMockInitialValues({});
    final state = AppState(await Storage.open(),
        rss: RssService(MockClient((_) async => http.Response(
            '<rss><channel><title>Kanaal Podcast</title></channel></rss>', 200))),
        youtube: FakeYouTube(),
        podcasts: podcasts);
    await tester.pumpWidget(MediaspelerApp(state: state));

    await tester.tap(find.text('Feed toevoegen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '@kanaal');
    await tester.tap(find.text('Toevoegen'));
    await tester.pumpAndSettle();

    expect(find.text('Podcastversie gevonden'), findsOneWidget);
    expect(find.text('Toch via YouTube'), findsOneWidget);
    await tester.tap(find.text('Als podcast toevoegen'));
    await tester.pumpAndSettle();

    expect(state.feeds.single.url, 'https://pod.example/feed');
    expect(state.feeds.single.isYouTube, isFalse);
    expect(find.text('Kanaal Podcast'), findsOneWidget, reason: 'staat in de lijst');
  });

  testWidgets('na herstart: "Verder vanaf" met de bewaarde plek', (tester) async {
    final state = await _state({
      'last_played': '{"id":"ep1","title":"Aflevering 1","uri":"https://x/e.mp3","kind":"audio"}',
      'pos:ep1': 754000,
    });
    await tester.pumpWidget(MediaspelerApp(state: state));
    expect(find.text('Verder vanaf 12:34'), findsOneWidget);
    expect(find.text('Aflevering 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Verbergen'));
    await tester.pump();
    expect(find.text('Verder vanaf 12:34'), findsNothing);
    expect(state.storage.lastPlayed(), isNull);
  });

  testWidgets('tabblad Nieuw toont afleveringen van alle feeds', (tester) async {
    final state = await _state({
      'feeds': '[{"url":"https://a.example/rss","title":"Podcast A","lastFetched":"${DateTime.now().toIso8601String()}"}]',
      'eps:https://a.example/rss':
          '[{"id":"a1","feedUrl":"https://a.example/rss","title":"Nieuwste aflevering","mediaUrl":"https://a.example/1.mp3","published":"${DateTime.now().toIso8601String()}"}]',
    });
    await tester.pumpWidget(MediaspelerApp(state: state));
    await tester.pumpAndSettle();
    expect(find.text('Nieuw'), findsWidgets);
    expect(find.text('Vandaag'), findsOneWidget);
    expect(find.text('Nieuwste aflevering'), findsOneWidget);
    expect(find.textContaining('Podcast A'), findsOneWidget);
  });
}
