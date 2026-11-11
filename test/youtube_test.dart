import 'package:flutter_test/flutter_test.dart';
import 'package:mediaspeler/models.dart';
import 'package:mediaspeler/services/rss_service.dart';
import 'package:mediaspeler/services/youtube_service.dart';
import 'package:xml/xml.dart';

void main() {
  group('YouTube-links herkennen', () {
    test('isYouTubeUrl', () {
      expect(isYouTubeUrl('https://www.youtube.com/@naam'), isTrue);
      expect(isYouTubeUrl('https://m.youtube.com/watch?v=dQw4w9WgXcQ'), isTrue);
      expect(isYouTubeUrl('https://youtu.be/dQw4w9WgXcQ'), isTrue);
      expect(isYouTubeUrl('https://music.youtube.com/playlist?list=PL1'), isTrue);
      expect(isYouTubeUrl('https://notyoutube.com/x'), isFalse);
      expect(isYouTubeUrl('https://example.com/feed.xml'), isFalse);
    });

    test('youtubeVideoId uit verschillende linkvormen', () {
      const id = 'dQw4w9WgXcQ';
      for (final url in [
        'https://www.youtube.com/watch?v=$id',
        'https://www.youtube.com/watch?v=$id&t=42s',
        'https://youtu.be/$id',
        'https://www.youtube.com/shorts/$id',
        'https://www.youtube.com/live/$id',
        'https://www.youtube.com/embed/$id',
      ]) {
        expect(youtubeVideoId(url), id, reason: url);
      }
      expect(youtubeVideoId('https://www.youtube.com/@naam'), isNull);
      expect(youtubeVideoId('https://www.youtube.com/watch?v=kort'), isNull);
      expect(youtubeVideoId('https://example.com/watch?v=$id'), isNull);
    });

    test('looksLikeYouTube accepteert ook @handle en links zonder https', () {
      expect(YouTubeService.looksLikeYouTube('@kanaal'), isTrue);
      expect(YouTubeService.looksLikeYouTube('youtube.com/@kanaal'), isTrue);
      expect(YouTubeService.looksLikeYouTube(' https://www.youtube.com/@kanaal '), isTrue);
      expect(YouTubeService.looksLikeYouTube('https://example.com/podcast.xml'), isFalse);
    });
  });

  group('directFeedUrl', () {
    const base = YouTubeService.feedBase;
    const ch = 'UC_x5XG1OV2P6uZZ5FSM9Ttw';

    test('kanaal-id', () {
      expect(YouTubeService.directFeedUrl('https://www.youtube.com/channel/$ch'),
          '$base?channel_id=$ch');
      expect(YouTubeService.directFeedUrl('youtube.com/channel/$ch/videos'),
          '$base?channel_id=$ch');
    });

    test('playlist, ook vanuit een video in een playlist', () {
      expect(YouTubeService.directFeedUrl('https://www.youtube.com/playlist?list=PLabc'),
          '$base?playlist_id=PLabc');
      expect(
          YouTubeService.directFeedUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLabc'),
          '$base?playlist_id=PLabc');
    });

    test('bestaande feedlink blijft gelijk', () {
      expect(YouTubeService.directFeedUrl('http://www.youtube.com/feeds/videos.xml?channel_id=$ch'),
          '$base?channel_id=$ch');
    });

    test('handles en losse video\'s hebben netwerk nodig', () {
      expect(YouTubeService.directFeedUrl('https://www.youtube.com/@naam'), isNull);
      expect(YouTubeService.directFeedUrl('https://youtu.be/dQw4w9WgXcQ'), isNull);
      expect(YouTubeService.directFeedUrl('https://example.com/channel/$ch'), isNull);
    });
  });

  group('pickAudio', () {
    AudioOption opt(int kbps) => AudioOption(Uri.parse('https://x/$kbps'), kbps * 1000);

    test('kiest de beste stream tot 96 kbit/s', () {
      // Typische YouTube-set: 49 (AAC), 128 (AAC), 48/64/133 (Opus).
      final pick = YouTubeService.pickAudio([opt(128), opt(49), opt(133), opt(64), opt(48)]);
      expect(pick!.bitsPerSecond, 64000);
    });

    test('valt terug op de zuinigste als alles zwaarder is', () {
      expect(YouTubeService.pickAudio([opt(160), opt(128)])!.bitsPerSecond, 128000);
    });

    test('lege lijst', () {
      expect(YouTubeService.pickAudio(const []), isNull);
    });
  });

  test('parseert een YouTube-kanaalfeed', () {
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/" xmlns="http://www.w3.org/2005/Atom">
 <id>yt:channel:abc</id>
 <title>Testkanaal</title>
 <entry>
  <id>yt:video:dQw4w9WgXcQ</id>
  <yt:videoId>dQw4w9WgXcQ</yt:videoId>
  <title>Eerste video</title>
  <link rel="alternate" href="https://www.youtube.com/watch?v=dQw4w9WgXcQ"/>
  <published>2026-10-29T20:00:20+00:00</published>
  <media:group>
   <media:title>Eerste video</media:title>
   <media:content url="https://www.youtube.com/v/dQw4w9WgXcQ?version=3" type="application/x-shockwave-flash" width="640" height="390"/>
   <media:thumbnail url="https://i3.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg" width="480" height="360"/>
   <media:description>Over deze video</media:description>
  </media:group>
 </entry>
</feed>''';
    final r = RssService().parse('https://www.youtube.com/feeds/videos.xml?channel_id=abc',
        XmlDocument.parse(xml));
    expect(r.feed.title, 'Testkanaal');
    final ep = r.episodes.single;
    expect(ep.id, 'yt:video:dQw4w9WgXcQ');
    expect(ep.mediaUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(ep.youtubeId, 'dQw4w9WgXcQ');
    expect(ep.kind, MediaKind.video);
    expect(ep.description, 'Over deze video');
    expect(ep.imageUrl, 'https://i3.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
    expect(ep.published!.toUtc(), DateTime.utc(2026, 10, 29, 20, 0, 20));

    final asAudio = MediaItem.fromEpisode(ep, feedTitle: 'Testkanaal', audioOnly: true);
    expect(asAudio.kind, MediaKind.audio);
    expect(asAudio.youtubeId, 'dQw4w9WgXcQ');
    expect(asAudio.id, ep.id, reason: 'zelfde id, dus gedeelde afspeelpositie');
    expect(MediaItem.fromEpisode(ep).kind, MediaKind.video);
  });

  test('Feed.audioOnly wordt bewaard en is standaard uit', () {
    const feed = Feed(url: 'https://www.youtube.com/feeds/videos.xml?channel_id=a', title: 'T');
    expect(feed.isYouTube, isTrue);
    expect(feed.audioOnly, isFalse);
    expect(Feed.fromJson(feed.copyWith(audioOnly: true).toJson()).audioOnly, isTrue);
    // Oude opgeslagen feeds zonder het veld.
    expect(Feed.fromJson({'url': 'u', 'title': 't'}).audioOnly, isFalse);
  });

  group('rustig aan bij blokkades', () {
    test('één nieuwe poging na een pauze, daarna lukt het', () async {
      final yt = _ScriptedYouTube([const YouTubeBlockedException(), Uri.parse('https://s/ok')]);
      final url = await yt.streamUrl('dQw4w9WgXcQ', audioOnly: true);
      expect(url.toString(), 'https://s/ok');
      expect(yt.calls, 2);
      expect(yt.slept, [YouTubeService.retryDelay]);
      expect(yt.isBlocked, isFalse);
    });

    test('twee keer geblokkeerd: afkoelperiode zonder nieuwe verzoeken', () async {
      final yt = _ScriptedYouTube([
        const YouTubeBlockedException(),
        const YouTubeBlockedException(),
        Uri.parse('https://s/later'),
      ]);
      await expectLater(
          yt.streamUrl('dQw4w9WgXcQ', audioOnly: true), throwsA(isA<YouTubeBlockedException>()));
      expect(yt.isBlocked, isTrue);

      // Andere video tijdens de afkoelperiode: direct een melding, geen verzoek.
      await expectLater(
          yt.streamUrl('jNQXAC9IVRw', audioOnly: true), throwsA(isA<YouTubeBlockedException>()));
      expect(yt.calls, 2);

      // Na de afkoelperiode wordt het weer geprobeerd.
      yt.clock = yt.clock.add(YouTubeService.cooldown + const Duration(seconds: 1));
      expect((await yt.streamUrl('jNQXAC9IVRw', audioOnly: true)).toString(), 'https://s/later');
      expect(yt.isBlocked, isFalse);
    });

    test('onspeelbare video wordt onthouden, andere video\'s gaan gewoon door', () async {
      final yt = _ScriptedYouTube([
        const YouTubeException('niet af te spelen'),
        Uri.parse('https://s/ander'),
      ]);
      await expectLater(yt.streamUrl('dQw4w9WgXcQ', audioOnly: true), throwsA(isA<YouTubeException>()));
      await expectLater(yt.streamUrl('dQw4w9WgXcQ', audioOnly: true), throwsA(isA<YouTubeException>()));
      expect(yt.calls, 1, reason: 'tweede keer niet opnieuw gevraagd');
      expect(yt.isBlocked, isFalse);
      expect((await yt.streamUrl('jNQXAC9IVRw', audioOnly: true)).toString(), 'https://s/ander');
    });

    test('gelukte stream wordt hergebruikt', () async {
      final yt = _ScriptedYouTube([Uri.parse('https://s/1')]);
      await yt.streamUrl('dQw4w9WgXcQ', audioOnly: true);
      await yt.streamUrl('dQw4w9WgXcQ', audioOnly: true);
      expect(yt.calls, 1);
    });
  });
}

/// YouTubeService met vooraf bepaalde antwoorden, een eigen klok en zonder echte pauzes.
class _ScriptedYouTube extends YouTubeService {
  final List<Object> script;
  int calls = 0;
  final List<Duration> slept = [];
  DateTime clock = DateTime(2026, 1, 1, 12);
  _ScriptedYouTube(this.script);

  @override
  DateTime now() => clock;

  @override
  Future<void> sleep(Duration d) async => slept.add(d);

  @override
  Future<Uri> fetchStream(String videoId, {required bool audioOnly}) async {
    final next = script[calls++];
    if (next is Exception) throw next;
    return next as Uri;
  }
}
