import 'package:flutter_test/flutter_test.dart';
import 'package:mediaspeler/models.dart';

Episode _episode({String url = 'https://example.com/a.mp3', String? mime}) => Episode(
      id: 'id',
      feedUrl: 'https://example.com/feed',
      title: 'Titel',
      mediaUrl: url,
      mimeType: mime,
    );

void main() {
  group('Episode.kind', () {
    test('herkent het mime-type', () {
      expect(_episode(mime: 'audio/mpeg').kind, MediaKind.audio);
      expect(_episode(mime: 'VIDEO/MP4').kind, MediaKind.video);
    });

    test('mime-type gaat voor de extensie', () {
      expect(_episode(url: 'https://x.nl/a.mp4', mime: 'audio/mp4').kind, MediaKind.audio);
    });

    test('valt terug op de bestandsextensie', () {
      for (final ext in ['mp4', 'm4v', 'mov', 'webm', 'mkv', 'm3u8']) {
        expect(_episode(url: 'https://x.nl/a.$ext').kind, MediaKind.video, reason: ext);
      }
      expect(_episode(url: 'https://x.nl/a.MP4?token=1').kind, MediaKind.video);
      expect(_episode(url: 'https://x.nl/a.mp3').kind, MediaKind.audio);
      expect(_episode(url: 'https://x.nl/stream').kind, MediaKind.audio);
    });
  });

  group('Feed', () {
    test('JSON heen en terug', () {
      final feed = Feed(
        url: 'https://example.com/feed',
        title: 'Podcast',
        description: 'Over dingen',
        imageUrl: 'https://example.com/c.jpg',
        lastFetched: DateTime.utc(2024, 1, 2, 3, 4, 5),
      );
      final back = Feed.fromJson(feed.toJson());
      expect(back.url, feed.url);
      expect(back.title, feed.title);
      expect(back.description, feed.description);
      expect(back.imageUrl, feed.imageUrl);
      expect(back.lastFetched, feed.lastFetched);
    });

    test('fromJson zonder titel gebruikt de URL', () {
      final feed = Feed.fromJson({'url': 'https://x.nl/rss'});
      expect(feed.title, 'https://x.nl/rss');
      expect(feed.lastFetched, isNull);
    });

    test('copyWith behoudt de URL en niet-gewijzigde velden', () {
      const feed = Feed(url: 'u', title: 'oud', description: 'd');
      final copy = feed.copyWith(title: 'nieuw');
      expect(copy.url, 'u');
      expect(copy.title, 'nieuw');
      expect(copy.description, 'd');
    });
  });

  group('LocalVideo', () {
    test('JSON heen en terug', () {
      final v = LocalVideo(uri: 'C:/v.mp4', name: 'v.mp4', added: DateTime.utc(2024, 5, 6));
      final back = LocalVideo.fromJson(v.toJson());
      expect(back.uri, v.uri);
      expect(back.name, v.name);
      expect(back.added, v.added);
    });

    test('ongeldige datum valt terug op nu', () {
      final v = LocalVideo.fromJson({'uri': 'x', 'name': 'x', 'added': 'onzin'});
      expect(DateTime.now().difference(v.added).inSeconds, lessThan(5));
    });
  });

  group('MediaItem', () {
    test('fromEpisode neemt de gegevens over', () {
      final item = MediaItem.fromEpisode(_episode(mime: 'video/mp4'), feedTitle: 'Kanaal');
      expect(item.id, 'id');
      expect(item.subtitle, 'Kanaal');
      expect(item.kind, MediaKind.video);
      expect(item.uri, 'https://example.com/a.mp3');
    });

    test('fromLocal is altijd een video met een eigen id', () {
      final item = MediaItem.fromLocal(
          LocalVideo(uri: 'content://1', name: 'film', added: DateTime(2024)));
      expect(item.id, 'local:content://1');
      expect(item.kind, MediaKind.video);
      expect(item.subtitle, 'Op dit apparaat');
    });
  });
}
