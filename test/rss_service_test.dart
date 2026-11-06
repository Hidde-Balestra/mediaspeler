import 'package:flutter_test/flutter_test.dart';
import 'package:mediaspeler/models.dart';
import 'package:mediaspeler/services/rss_service.dart';
import 'package:xml/xml.dart';

void main() {
  final rss = RssService();

  test('parseert een RSS-podcastfeed', () {
    const xml = '''<?xml version="1.0"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>Testpodcast</title>
    <description>Over &lt;b&gt;testen&lt;/b&gt;</description>
    <itunes:image href="https://example.com/cover.jpg"/>
    <item>
      <title>Aflevering 1</title>
      <guid>ep1</guid>
      <pubDate>Tue, 05 Nov 2024 10:00:00 +0100</pubDate>
      <itunes:duration>1:02:03</itunes:duration>
      <enclosure url="https://example.com/ep1.mp3" type="audio/mpeg" length="1"/>
    </item>
    <item>
      <title>Video-aflevering</title>
      <enclosure url="https://example.com/ep2.mp4" type="video/mp4" length="1"/>
    </item>
    <item><title>Zonder media</title></item>
  </channel>
</rss>''';
    final r = rss.parse('https://example.com/feed', XmlDocument.parse(xml));
    expect(r.feed.title, 'Testpodcast');
    expect(r.feed.description, 'Over testen');
    expect(r.feed.imageUrl, 'https://example.com/cover.jpg');
    expect(r.episodes, hasLength(2));
    expect(r.episodes[0].id, 'ep1');
    expect(r.episodes[0].duration, const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(r.episodes[0].published!.toUtc(), DateTime.utc(2024, 11, 5, 9));
    expect(r.episodes[0].kind, MediaKind.audio);
    expect(r.episodes[1].kind, MediaKind.video);
    expect(r.episodes[1].imageUrl, 'https://example.com/cover.jpg');
  });

  test('parseert een Atom-feed met enclosure-link', () {
    const xml = '''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atomkanaal</title>
  <entry>
    <id>a1</id>
    <title>Item</title>
    <published>2024-01-02T03:04:05Z</published>
    <link rel="enclosure" href="https://example.com/a1.webm" type="video/webm"/>
  </entry>
</feed>''';
    final r = rss.parse('https://example.com/atom', XmlDocument.parse(xml));
    expect(r.feed.title, 'Atomkanaal');
    expect(r.episodes.single.mediaUrl, 'https://example.com/a1.webm');
    expect(r.episodes.single.kind, MediaKind.video);
  });
}
