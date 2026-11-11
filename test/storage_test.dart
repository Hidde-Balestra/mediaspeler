import 'package:flutter_test/flutter_test.dart';
import 'package:mediaspeler/models.dart';
import 'package:mediaspeler/services/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('lege opslag geeft lege lijsten', () async {
    final s = await Storage.open();
    expect(s.loadFeeds(), isEmpty);
    expect(s.loadLocalVideos(), isEmpty);
    expect(s.finished(), isEmpty);
    expect(s.themeMode(), isNull);
  });

  test('feeds en lokale video\'s worden bewaard', () async {
    final s = await Storage.open();
    await s.saveFeeds(const [Feed(url: 'https://a.nl', title: 'A')]);
    await s.saveLocalVideos([LocalVideo(uri: 'v', name: 'V', added: DateTime(2024))]);

    final again = await Storage.open();
    expect(again.loadFeeds().single.title, 'A');
    expect(again.loadLocalVideos().single.name, 'V');
  });

  test('kapotte JSON geeft een lege lijst', () async {
    SharedPreferences.setMockInitialValues({'feeds': '{niet geldig'});
    final s = await Storage.open();
    expect(s.loadFeeds(), isEmpty);
  });

  test('afspeelposities', () async {
    final s = await Storage.open();
    expect(s.position('x'), isNull);
    await s.savePosition('x', const Duration(seconds: 42));
    expect(s.position('x'), const Duration(seconds: 42));
    await s.clearPosition('x');
    expect(s.position('x'), isNull);
  });

  test('beluisterd markeren en weer weghalen', () async {
    final s = await Storage.open();
    await s.setFinished('a', true);
    await s.setFinished('b', true);
    expect(s.finished(), {'a', 'b'});
    await s.setFinished('a', false);
    expect(s.finished(), {'b'});
  });

  test('thema-voorkeur', () async {
    final s = await Storage.open();
    await s.setThemeMode('dark');
    expect((await Storage.open()).themeMode(), 'dark');
  });

  test('laatst gespeeld en afleveringen per feed', () async {
    final s = await Storage.open();
    expect(s.lastPlayed(), isNull);
    const item = MediaItem(
        id: 'yt:video:x', title: 'T', uri: 'https://www.youtube.com/watch?v=x',
        kind: MediaKind.audio, subtitle: 'Kanaal', youtubeId: 'x');
    await s.setLastPlayed(item);
    final back = (await Storage.open()).lastPlayed()!;
    expect(back.id, item.id);
    expect(back.kind, MediaKind.audio);
    expect(back.youtubeId, 'x');
    await s.setLastPlayed(null);
    expect(s.lastPlayed(), isNull);

    final ep = Episode(
        id: 'e', feedUrl: 'f', title: 'Ep', mediaUrl: 'https://x/e.mp3',
        published: DateTime.utc(2024, 1, 2), duration: const Duration(minutes: 3));
    await s.saveEpisodes('f', [ep]);
    final eps = s.loadEpisodes('f');
    expect(eps.single.title, 'Ep');
    expect(eps.single.published, DateTime.utc(2024, 1, 2));
    expect(eps.single.duration, const Duration(minutes: 3));
    await s.clearEpisodes('f');
    expect(s.loadEpisodes('f'), isEmpty);
  });
}
