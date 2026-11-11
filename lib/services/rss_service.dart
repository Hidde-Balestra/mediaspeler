import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models.dart';

class FeedResult {
  final Feed feed;
  final List<Episode> episodes;
  const FeedResult(this.feed, this.episodes);
}

/// Haalt RSS 2.0- en Atom-feeds op en zet ze om naar [Feed] + [Episode]s.
/// Alleen items met een afspeelbaar media-bestand (enclosure / media:content)
/// worden meegenomen.
class RssService {
  final http.Client _client;
  RssService([http.Client? client]) : _client = client ?? http.Client();

  /// Dezelfde HTTP-client, ook voor het herkennen van links (en in tests te vervangen).
  http.Client get client => _client;

  Future<FeedResult> fetch(String url) async {
    final uri = Uri.parse(url.trim());
    final res = await _client.get(uri, headers: {
      'User-Agent': 'Mediaspeler/1.0 (Flutter podcast app)',
      'Accept': 'application/rss+xml, application/atom+xml, application/xml, text/xml, */*',
    }).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('Feed gaf HTTP ${res.statusCode}');
    }
    return parse(url, XmlDocument.parse(_decode(res)));
  }

  /// Probeer UTF-8 (meest gangbaar, ook als de server geen charset meegeeft);
  /// val terug op wat de server opgeeft.
  String _decode(http.Response res) {
    try {
      return utf8.decode(res.bodyBytes);
    } on FormatException {
      return res.body;
    }
  }

  FeedResult parse(String url, XmlDocument doc) {
    final root = doc.rootElement;
    if (root.localName == 'feed') return _parseAtom(url, root);
    final channel = _child(root, 'channel');
    if (channel == null) throw const FormatException('Geen geldige RSS- of Atom-feed');
    return _parseRss(url, channel);
  }

  FeedResult _parseRss(String url, XmlElement channel) {
    final feedImage = _attr(_child(channel, 'image', ns: 'itunes'), 'href') ??
        _text(_child(_child(channel, 'image'), 'url'));
    final feed = Feed(
      url: url,
      title: _text(_child(channel, 'title')) ?? url,
      description: _stripHtml(_text(_child(channel, 'description'))),
      imageUrl: feedImage,
      lastFetched: DateTime.now(),
    );

    final episodes = <Episode>[];
    for (final item in channel.findElements('item')) {
      final media = _findMedia(item);
      if (media == null) continue;
      final title = _text(_child(item, 'title')) ?? 'Zonder titel';
      episodes.add(Episode(
        id: _text(_child(item, 'guid')) ?? media.$1,
        feedUrl: url,
        title: title,
        description: _stripHtml(_text(_child(item, 'summary', ns: 'itunes')) ??
            _text(_child(item, 'description'))),
        mediaUrl: media.$1,
        mimeType: media.$2,
        published: _parseDate(_text(_child(item, 'pubDate'))),
        duration: _parseDuration(_text(_child(item, 'duration', ns: 'itunes'))),
        imageUrl: _attr(_child(item, 'image', ns: 'itunes'), 'href') ??
            _mediaThumb(item) ??
            feedImage,
      ));
    }
    return FeedResult(feed, episodes);
  }

  FeedResult _parseAtom(String url, XmlElement root) {
    final feedImage = _text(_child(root, 'logo')) ?? _text(_child(root, 'icon'));
    final feed = Feed(
      url: url,
      title: _text(_child(root, 'title')) ?? url,
      description: _stripHtml(_text(_child(root, 'subtitle'))),
      imageUrl: feedImage,
      lastFetched: DateTime.now(),
    );
    final episodes = <Episode>[];
    for (final entry in root.findElements('entry')) {
      (String, String?)? media;
      String? description;
      // YouTube-kanaal/-playlist: de kijk-link; de stream wordt pas bij afspelen opgehaald.
      final ytId = _text(_child(entry, 'videoId', ns: 'yt'));
      if (ytId != null) {
        media = ('https://www.youtube.com/watch?v=$ytId', 'video/youtube');
        description = _text(_child(_child(entry, 'group', ns: 'media'), 'description', ns: 'media'));
      }
      for (final link in entry.findElements('link')) {
        if (link.getAttribute('rel') == 'enclosure') {
          final href = link.getAttribute('href');
          if (href != null) media = (href, link.getAttribute('type'));
        }
      }
      media ??= _findMedia(entry);
      if (media == null) continue;
      episodes.add(Episode(
        id: _text(_child(entry, 'id')) ?? media.$1,
        feedUrl: url,
        title: _text(_child(entry, 'title')) ?? 'Zonder titel',
        description: _stripHtml(description ??
            _text(_child(entry, 'summary')) ??
            _text(_child(entry, 'content'))),
        mediaUrl: media.$1,
        mimeType: media.$2,
        published: DateTime.tryParse(
            _text(_child(entry, 'published')) ?? _text(_child(entry, 'updated')) ?? ''),
        imageUrl: _mediaThumb(entry) ?? feedImage,
      ));
    }
    return FeedResult(feed, episodes);
  }

  /// Zoekt een enclosure of media:content (ook binnen media:group).
  (String, String?)? _findMedia(XmlElement item) {
    final enc = _child(item, 'enclosure');
    final encUrl = _attr(enc, 'url');
    if (encUrl != null) return (encUrl, _attr(enc, 'type'));

    final candidates = [
      ...item.findElements('content', namespace: _mediaNs),
      ..._children(item, 'group', ns: 'media')
          .expand((g) => g.findElements('content', namespace: _mediaNs)),
    ];
    for (final c in candidates) {
      final u = c.getAttribute('url');
      final type = c.getAttribute('type');
      final medium = c.getAttribute('medium');
      if (u == null) continue;
      if (type == null && medium == null) return (u, null);
      if ((type ?? '').startsWith('audio') || (type ?? '').startsWith('video')) {
        return (u, type);
      }
      if (medium == 'audio' || medium == 'video') return (u, '$medium/*');
    }
    return null;
  }

  String? _mediaThumb(XmlElement item) {
    final t = _child(item, 'thumbnail', ns: 'media') ??
        _children(item, 'group', ns: 'media')
            .map((g) => _child(g, 'thumbnail', ns: 'media'))
            .firstWhere((e) => e != null, orElse: () => null);
    return _attr(t, 'url');
  }

  // ---- XML-hulpfuncties (namespace-tolerant op prefix) ----

  static const _mediaNs = 'http://search.yahoo.com/mrss/';

  Iterable<XmlElement> _children(XmlElement? el, String local, {String? ns}) {
    if (el == null) return const [];
    return el.childElements.where((c) =>
        c.name.local == local && (ns == null ? c.name.prefix == null : c.name.prefix == ns));
  }

  XmlElement? _child(XmlElement? el, String local, {String? ns}) {
    final list = _children(el, local, ns: ns);
    return list.isEmpty ? null : list.first;
  }

  String? _text(XmlElement? el) {
    final t = el?.innerText.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  String? _attr(XmlElement? el, String name) {
    final v = el?.getAttribute(name)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  String? _stripHtml(String? s) {
    if (s == null) return null;
    return s
        .replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  Duration? _parseDuration(String? s) {
    if (s == null) return null;
    final parts = s.split(':').map((p) => int.tryParse(p.trim())).toList();
    if (parts.any((p) => p == null)) return null;
    var seconds = 0;
    for (final p in parts) {
      seconds = seconds * 60 + p!;
    }
    return Duration(seconds: seconds);
  }

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// RFC 822-datum, bijv. "Tue, 05 Nov 2024 10:00:00 +0100".
  DateTime? _parseDate(String? s) {
    if (s == null) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    final m = RegExp(
            r'(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Z]{1,4})?')
        .firstMatch(s);
    if (m == null) return null;
    final month = _months[m.group(2)!.toLowerCase()];
    if (month == null) return null;
    var year = int.parse(m.group(3)!);
    if (year < 100) year += 2000;
    var dt = DateTime.utc(year, month, int.parse(m.group(1)!), int.parse(m.group(4)!),
        int.parse(m.group(5)!), int.tryParse(m.group(6) ?? '0') ?? 0);
    final tz = m.group(7);
    if (tz != null && RegExp(r'^[+-]\d{4}$').hasMatch(tz)) {
      final sign = tz.startsWith('-') ? -1 : 1;
      final offset = Duration(
          hours: int.parse(tz.substring(1, 3)), minutes: int.parse(tz.substring(3, 5)));
      dt = sign == 1 ? dt.subtract(offset) : dt.add(offset);
    }
    return dt.toLocal();
  }
}
