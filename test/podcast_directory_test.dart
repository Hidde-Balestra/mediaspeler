import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mediaspeler/services/podcast_directory.dart';

Map<String, dynamic> _result(String title, String author, String? feed) => {
      'collectionName': title,
      'artistName': author,
      'feedUrl': ?feed,
      'artworkUrl600': 'https://img.example/$title.jpg',
    };

http.Response _json(List<Map<String, dynamic>> results) => http.Response.bytes(
    utf8.encode(jsonEncode({'resultCount': results.length, 'results': results})), 200);

void main() {
  group('similarity', () {
    test('negeert hoofdletters, accenten en woorden als "podcast"', () {
      expect(PodcastDirectory.similarity('Lex Fridman', 'Lex Fridman Podcast'), 1);
      expect(PodcastDirectory.similarity('Café Weltschmerz', 'cafe weltschmerz'), 1);
      expect(PodcastDirectory.similarity('The Official Daily Show', 'Daily Show'), 1);
    });

    test('gedeeltelijke en geen overlap', () {
      expect(PodcastDirectory.similarity('Tech Talk Weekly', 'Tech Talk'), closeTo(2 / 3, 0.01));
      expect(PodcastDirectory.similarity('Koken met Jan', 'Voetbal Inside'), 0);
      expect(PodcastDirectory.similarity('Podcast', 'The Show'), 0, reason: 'alleen ruis');
      expect(PodcastDirectory.similarity('The Podcast', 'the podcast'), 1);
    });
  });

  group('bestMatch', () {
    test('kiest de beste boven de drempel, ook op naam van de maker', () {
      const results = [
        PodcastMatch(title: 'Iets anders', author: 'Iemand', feedUrl: 'a'),
        PodcastMatch(title: 'Gesprekken', author: 'Kanaal Naam', feedUrl: 'b'),
        PodcastMatch(title: 'Kanaal Naam Extra Lang', author: 'X', feedUrl: 'c'),
      ];
      final best = PodcastDirectory.bestMatch('Kanaal Naam', results)!;
      expect(best.feedUrl, 'b');
      expect(best.score, 1);
    });

    test('niets als geen enkel resultaat goed genoeg lijkt', () {
      const results = [PodcastMatch(title: 'Heel iets anders', author: 'Y', feedUrl: 'a')];
      expect(PodcastDirectory.bestMatch('Kanaal Naam', results), isNull);
    });
  });

  group('zoeken', () {
    test('leest de iTunes-resultaten en slaat items zonder feed over', () async {
      late Uri asked;
      final dir = PodcastDirectory(MockClient((req) async {
        asked = req.url;
        return _json([
          _result('Lex Fridman Podcast', 'Lex Fridman', 'https://lexfridman.com/feed/podcast/'),
          _result('Zonder feed', 'X', null),
        ]);
      }));
      final results = await dir.search('Lex Fridman');
      expect(asked.host, 'itunes.apple.com');
      expect(asked.queryParameters['media'], 'podcast');
      expect(asked.queryParameters['term'], 'Lex Fridman');
      expect(results.single.feedUrl, 'https://lexfridman.com/feed/podcast/');
      expect(results.single.imageUrl, contains('Lex Fridman Podcast'));
    });

    test('findFor zoekt eerst in NL en daarna in US', () async {
      final countries = <String>[];
      final dir = PodcastDirectory(MockClient((req) async {
        final c = req.url.queryParameters['country']!;
        countries.add(c);
        return c == 'NL'
            ? _json([])
            : _json([_result('Kanaal', 'Kanaal', 'https://pod.example/feed')]);
      }));
      final match = await dir.findFor('Kanaal');
      expect(countries, ['NL', 'US']);
      expect(match!.feedUrl, 'https://pod.example/feed');
    });

    test('findFor stopt bij een match in NL', () async {
      final countries = <String>[];
      final dir = PodcastDirectory(MockClient((req) async {
        countries.add(req.url.queryParameters['country']!);
        return _json([_result('Kanaal', 'Kanaal', 'https://pod.example/feed')]);
      }));
      await dir.findFor('Kanaal');
      expect(countries, ['NL']);
    });

    test('netwerkfout of HTTP-fout geeft geen match', () async {
      final kapot = PodcastDirectory(MockClient((_) async => throw http.ClientException('weg')));
      expect(await kapot.findFor('Kanaal'), isNull);
      final fout = PodcastDirectory(MockClient((_) async => http.Response('nee', 503)));
      expect(await fout.findFor('Kanaal'), isNull);
    });
  });

  group('handle', () {
    test('handleScore vergelijkt de handle met de naam zonder spaties', () {
      expect(PodcastDirectory.handleScore('@hubermanlab', 'Huberman Lab'), 1);
      expect(PodcastDirectory.handleScore('lexfridman', 'Lex Fridman Podcast'), 0.9);
      expect(PodcastDirectory.handleScore('@nos', 'NOS'), 0, reason: 'te kort om te vertrouwen');
      expect(PodcastDirectory.handleScore('@veritasium', 'Science Vs'), 0);
    });

    test('vindt de podcast als kanaal- en podcastnaam verschillen', () async {
      final terms = <String>[];
      final dir = PodcastDirectory(MockClient((req) async {
        final term = req.url.queryParameters['term']!;
        terms.add(term);
        return term == 'hubermanlab'
            ? _json([_result('Huberman Lab', 'Scicomm Media', 'https://huberman.example/feed')])
            : _json([_result('Iets anders', 'Iemand', 'https://x.example/feed')]);
      }));
      final m = await dir.findFor('Andrew Huberman', handle: '@hubermanlab');
      expect(m!.feedUrl, 'https://huberman.example/feed');
      expect(terms, ['Andrew Huberman', 'hubermanlab']);
    });

    test('zoekt niet dubbel als handle gelijk is aan de naam', () async {
      final terms = <String>[];
      final dir = PodcastDirectory(MockClient((req) async {
        terms.add(req.url.queryParameters['term']!);
        return _json([]);
      }));
      await dir.findFor('Veritasium', handle: '@veritasium');
      expect(terms, ['Veritasium', 'Veritasium'], reason: 'alleen NL en US met de naam');
    });
  });

  test('korte namen: ook de maker moet kloppen', () {
    const results = [
      PodcastMatch(title: 'NOS', author: 'Il podcast ufficiale Alta Badia', feedUrl: 'fout'),
      PodcastMatch(title: 'NOS Met het Oog op Morgen', author: 'NOS', feedUrl: 'goed'),
    ];
    expect(PodcastDirectory.bestMatch('NOS', results)!.feedUrl, 'goed');
    expect(PodcastDirectory.bestMatch('NOS', results.take(1).toList()), isNull);
  });
}
