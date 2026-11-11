import 'dart:convert';

import 'package:http/http.dart' as http;

/// Een podcast uit de openbare podcastgids van Apple.
class PodcastMatch {
  final String title;
  final String author;
  final String feedUrl;
  final String? imageUrl;
  final double score;
  const PodcastMatch({
    required this.title,
    required this.author,
    required this.feedUrl,
    this.imageUrl,
    this.score = 0,
  });
}

/// Zoekt de gewone podcastversie van een YouTube-kanaal op, via de gratis
/// iTunes Search API (geen account of sleutel nodig). Veel kanalen met
/// gesprekken of shows publiceren ook een podcastfeed: die is echt alleen
/// audio, werkt op de achtergrond en heeft geen last van YouTube's bot-controle.
class PodcastDirectory {
  static const minScore = 0.6;

  final http.Client _client;
  PodcastDirectory([http.Client? client]) : _client = client ?? http.Client();

  Future<List<PodcastMatch>> search(String term, {String country = 'NL'}) async {
    final uri = Uri.https('itunes.apple.com', '/search', {
      'media': 'podcast',
      'entity': 'podcast',
      'limit': '10',
      'country': country,
      'term': term,
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return const [];
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final r in (body['results'] as List? ?? const []).cast<Map<String, dynamic>>())
        if (r['feedUrl'] is String && (r['feedUrl'] as String).isNotEmpty)
          PodcastMatch(
            title: r['collectionName'] as String? ?? '',
            author: r['artistName'] as String? ?? '',
            feedUrl: r['feedUrl'] as String,
            imageUrl: (r['artworkUrl600'] ?? r['artworkUrl100']) as String?,
          ),
    ];
  }

  /// De best passende podcast bij [channelTitle], of null als niets goed genoeg lijkt.
  /// Zoekt eerst in de Nederlandse gids en daarna in de Amerikaanse.
  /// Met [handle] (bijv. `@hubermanlab`) wordt ook daarop gezocht en vergeleken:
  /// kanaalnaam en podcastnaam verschillen soms ("Andrew Huberman" vs "Huberman Lab").
  Future<PodcastMatch?> findFor(String channelTitle, {String? handle}) async {
    final h = handle?.replaceFirst('@', '');
    final terms = [
      channelTitle,
      if (h != null && h.length >= 5 && _compact(h) != _compact(channelTitle)) h,
    ];
    for (final country in const ['NL', 'US']) {
      for (final term in terms) {
        final List<PodcastMatch> results;
        try {
          results = await search(term, country: country);
        } catch (_) {
          return null; // Zoeken is een extraatje; zonder netwerk gewoon doorgaan.
        }
        final best = bestMatch(channelTitle, results, handle: h);
        if (best != null) return best;
      }
    }
    return null;
  }

  /// Kiest het resultaat waarvan titel of maker het meest op de kanaalnaam
  /// (of de handle) lijkt.
  static PodcastMatch? bestMatch(String channelTitle, List<PodcastMatch> results,
      {String? handle}) {
    PodcastMatch? best;
    // Korte namen ("NOS") komen vaak toevallig overeen: dan moet ook de maker kloppen.
    final short = _compact(channelTitle).length < 5;
    for (final r in results) {
      if (short && similarity(channelTitle, r.author) < minScore) continue;
      final score = [
        similarity(channelTitle, r.title),
        similarity(channelTitle, r.author),
        if (handle != null) ...[handleScore(handle, r.title), handleScore(handle, r.author)],
      ].reduce((a, b) => a > b ? a : b);
      if (score >= minScore && (best == null || score > best.score)) {
        best = PodcastMatch(
            title: r.title,
            author: r.author,
            feedUrl: r.feedUrl,
            imageUrl: r.imageUrl,
            score: score);
      }
    }
    return best;
  }

  /// Handles zijn aaneengeschreven ("hubermanlab"); vergelijk met de naam zonder spaties.
  static double handleScore(String handle, String name) {
    final h = _compact(handle.replaceFirst('@', ''));
    final n = _compact(name);
    if (h.length < 5 || n.length < 5) return 0;
    if (h == n) return 1;
    // "lexfridman" ↔ "lexfridmanpodcast"
    if (n.startsWith(h) || h.startsWith(n)) return 0.9;
    return 0;
  }

  static String _compact(String s) => _words(s, keepNoise: true).join();

  static const _noise = {
    'podcast', 'podcasts', 'the', 'de', 'het', 'official', 'officieel', 'show',
    'tv', 'channel', 'kanaal', 'videos', 'video', 'with', 'met', 'and', 'en',
  };

  static Iterable<String> _words(String s, {bool keepNoise = false}) {
    const accents = {'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'é': 'e', 'è': 'e', 'ë': 'e',
      'ê': 'e', 'í': 'i', 'ï': 'i', 'ó': 'o', 'ö': 'o', 'ô': 'o', 'ú': 'u', 'ü': 'u', 'ç': 'c'};
    var t = s.toLowerCase();
    accents.forEach((k, v) => t = t.replaceAll(k, v));
    final words = t.split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty);
    if (keepNoise) return words;
    final all = words.toSet();
    final meaningful = all.difference(_noise);
    // Naam bestaat alleen uit "ruis" (bijv. "The Podcast"): dan alles meetellen.
    return meaningful.isEmpty ? all : meaningful;
  }

  /// Overlap van betekenisvolle woorden (0..1), ongevoelig voor hoofdletters,
  /// accenten en woorden als "podcast" of "official".
  static double similarity(String a, String b) {
    final wa = _words(a).toSet(), wb = _words(b).toSet();
    if (wa.isEmpty || wb.isEmpty) return 0;
    if (wa.join(' ') == wb.join(' ')) return 1;
    final common = wa.intersection(wb).length;
    return common / wa.union(wb).length;
  }
}
