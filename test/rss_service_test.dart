import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  test('media:content binnen media:group met thumbnail', () {
    const xml = '''<?xml version="1.0"?>
<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
  <channel>
    <title>Kanaal</title>
    <image><url>https://example.com/logo.png</url></image>
    <item>
      <title>Clip</title>
      <media:group>
        <media:content url="https://example.com/clip.jpg" medium="image"/>
        <media:content url="https://example.com/clip.mp4" medium="video"/>
        <media:thumbnail url="https://example.com/thumb.jpg"/>
      </media:group>
    </item>
  </channel>
</rss>''';
    final r = rss.parse('u', XmlDocument.parse(xml));
    expect(r.feed.imageUrl, 'https://example.com/logo.png');
    final ep = r.episodes.single;
    expect(ep.mediaUrl, 'https://example.com/clip.mp4');
    expect(ep.mimeType, 'video/*');
    expect(ep.kind, MediaKind.video);
    expect(ep.imageUrl, 'https://example.com/thumb.jpg');
    expect(ep.id, 'https://example.com/clip.mp4', reason: 'zonder guid is de media-URL het id');
  });

  test('beschrijving: HTML en entities worden opgeschoond', () {
    const xml = '''<rss><channel><title>T</title><item>
      <title>X</title>
      <description><![CDATA[<p>Regel&nbsp;1</p><p>Tom &amp; Jerry<br/>"quote"</p>]]></description>
      <enclosure url="https://e.nl/x.mp3" type="audio/mpeg"/>
    </item></channel></rss>''';
    final ep = rss.parse('u', XmlDocument.parse(xml)).episodes.single;
    expect(ep.description, 'Regel 1\nTom & Jerry\n"quote"');
  });

  test('itunes:summary gaat voor description, duur in seconden of mm:ss', () {
    const xml = '''<rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>T</title>
      <item><title>A</title><description>lang</description><itunes:summary>kort</itunes:summary>
        <itunes:duration>3600</itunes:duration>
        <enclosure url="https://e.nl/a.mp3"/></item>
      <item><title>B</title><itunes:duration>12:34</itunes:duration>
        <enclosure url="https://e.nl/b.mp3"/></item>
      <item><title>C</title><itunes:duration>onbekend</itunes:duration>
        <enclosure url="https://e.nl/c.mp3"/></item>
    </channel></rss>''';
    final eps = rss.parse('u', XmlDocument.parse(xml)).episodes;
    expect(eps[0].description, 'kort');
    expect(eps[0].duration, const Duration(hours: 1));
    expect(eps[1].duration, const Duration(minutes: 12, seconds: 34));
    expect(eps[2].duration, isNull);
  });

  test('datums: RFC 822 met GMT, tweecijferig jaar en ISO', () {
    String item(String date) => '<item><title>x</title><pubDate>$date</pubDate>'
        '<enclosure url="https://e.nl/$date.mp3"/></item>';
    final xml = '<rss><channel><title>T</title>'
        '${item('Mon, 01 Jan 2024 12:00:00 GMT')}'
        '${item('5 Feb 24 08:30 -0200')}'
        '${item('2024-03-04T05:06:07Z')}'
        '${item('geen datum')}'
        '</channel></rss>';
    final eps = rss.parse('u', XmlDocument.parse(xml)).episodes;
    expect(eps[0].published!.toUtc(), DateTime.utc(2024, 1, 1, 12));
    expect(eps[1].published!.toUtc(), DateTime.utc(2024, 2, 5, 10, 30));
    expect(eps[2].published!.toUtc(), DateTime.utc(2024, 3, 4, 5, 6, 7));
    expect(eps[3].published, isNull);
  });

  test('ongeldig document geeft een FormatException', () {
    expect(() => rss.parse('u', XmlDocument.parse('<html><body/></html>')),
        throwsFormatException);
  });

  group('fetch', () {
    test('haalt op met de juiste headers en decodeert UTF-8', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response.bytes(
            utf8.encode('<rss><channel><title>Café ☕</title></channel></rss>'), 200,
            headers: {'content-type': 'application/xml'});
      });
      final r = await RssService(client).fetch(' https://example.com/rss ');
      expect(seen.url.toString(), 'https://example.com/rss');
      expect(seen.headers['User-Agent'], startsWith('Mediaspeler/'));
      expect(r.feed.title, 'Café ☕');
    });

    test('HTTP-fout geeft een duidelijke melding', () async {
      final client = MockClient((_) async => http.Response('nee', 404));
      expect(
        RssService(client).fetch('https://example.com/rss'),
        throwsA(predicate((e) => e.toString().contains('HTTP 404'))),
      );
    });
  });
}
