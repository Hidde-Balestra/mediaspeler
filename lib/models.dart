/// Datamodellen voor feeds, afleveringen en lokale video's.
library;

enum MediaKind { audio, video }

final _ytHost = RegExp(r'^(www\.|m\.|music\.)?(youtube\.com|youtube-nocookie\.com)$|^youtu\.be$');
final _ytId = RegExp(r'^[\w-]{11}$');

/// Of [url] naar YouTube wijst.
bool isYouTubeUrl(String url) {
  final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
  return _ytHost.hasMatch(host);
}

/// Haalt het video-id uit een YouTube-link (watch, youtu.be, shorts, live, embed).
String? youtubeVideoId(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !isYouTubeUrl(url)) return null;
  String? id;
  if (uri.host.toLowerCase() == 'youtu.be') {
    id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
  } else if (uri.queryParameters['v'] != null) {
    id = uri.queryParameters['v'];
  } else if (uri.pathSegments.length >= 2 &&
      const ['shorts', 'live', 'embed', 'v'].contains(uri.pathSegments.first)) {
    id = uri.pathSegments[1];
  }
  return id != null && _ytId.hasMatch(id) ? id : null;
}

class Feed {
  final String url;
  final String title;
  final String? description;
  final String? imageUrl;
  final DateTime? lastFetched;

  /// Video's uit deze feed afspelen als podcast: alleen de audio ophalen.
  final bool audioOnly;

  const Feed({
    required this.url,
    required this.title,
    this.description,
    this.imageUrl,
    this.lastFetched,
    this.audioOnly = false,
  });

  bool get isYouTube => isYouTubeUrl(url);

  Feed copyWith({
    String? title,
    String? description,
    String? imageUrl,
    DateTime? lastFetched,
    bool? audioOnly,
  }) =>
      Feed(
        url: url,
        title: title ?? this.title,
        description: description ?? this.description,
        imageUrl: imageUrl ?? this.imageUrl,
        lastFetched: lastFetched ?? this.lastFetched,
        audioOnly: audioOnly ?? this.audioOnly,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'description': description,
        'imageUrl': imageUrl,
        'lastFetched': lastFetched?.toIso8601String(),
        'audioOnly': audioOnly,
      };

  factory Feed.fromJson(Map<String, dynamic> j) => Feed(
        url: j['url'] as String,
        title: j['title'] as String? ?? j['url'] as String,
        description: j['description'] as String?,
        imageUrl: j['imageUrl'] as String?,
        lastFetched: j['lastFetched'] != null
            ? DateTime.tryParse(j['lastFetched'] as String)
            : null,
        audioOnly: j['audioOnly'] as bool? ?? false,
      );
}

class Episode {
  final String id;
  final String feedUrl;
  final String title;
  final String? description;
  final String mediaUrl;
  final String? mimeType;
  final DateTime? published;
  final Duration? duration;
  final String? imageUrl;

  const Episode({
    required this.id,
    required this.feedUrl,
    required this.title,
    required this.mediaUrl,
    this.description,
    this.mimeType,
    this.published,
    this.duration,
    this.imageUrl,
  });

  /// Video-id als dit een YouTube-video is (de stream wordt pas bij afspelen opgehaald).
  String? get youtubeId => youtubeVideoId(mediaUrl);

  MediaKind get kind {
    if (youtubeId != null) return MediaKind.video;
    final mime = mimeType?.toLowerCase() ?? '';
    if (mime.startsWith('video')) return MediaKind.video;
    if (mime.startsWith('audio')) return MediaKind.audio;
    final path = Uri.tryParse(mediaUrl)?.path.toLowerCase() ?? '';
    const videoExt = ['.mp4', '.m4v', '.mov', '.webm', '.mkv', '.m3u8'];
    return videoExt.any(path.endsWith) ? MediaKind.video : MediaKind.audio;
  }
}

class LocalVideo {
  /// Bestandspad (Windows/iOS) of content:// URI (Android).
  final String uri;
  final String name;
  final DateTime added;

  const LocalVideo({required this.uri, required this.name, required this.added});

  Map<String, dynamic> toJson() =>
      {'uri': uri, 'name': name, 'added': added.toIso8601String()};

  factory LocalVideo.fromJson(Map<String, dynamic> j) => LocalVideo(
        uri: j['uri'] as String,
        name: j['name'] as String,
        added: DateTime.tryParse(j['added'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Iets dat afgespeeld kan worden: een aflevering of een lokale video.
class MediaItem {
  final String id;
  final String title;
  final String? subtitle;
  final String uri;
  final MediaKind kind;
  final String? imageUrl;

  /// Gezet voor YouTube-video's; [uri] is dan de kijk-link, niet de stream.
  final String? youtubeId;

  const MediaItem({
    required this.id,
    required this.title,
    required this.uri,
    required this.kind,
    this.subtitle,
    this.imageUrl,
    this.youtubeId,
  });

  /// Met [audioOnly] wordt een video als audio afgespeeld (zonder beeld).
  factory MediaItem.fromEpisode(Episode e, {String? feedTitle, bool audioOnly = false}) =>
      MediaItem(
        id: e.id,
        title: e.title,
        subtitle: feedTitle,
        uri: e.mediaUrl,
        kind: audioOnly ? MediaKind.audio : e.kind,
        imageUrl: e.imageUrl,
        youtubeId: e.youtubeId,
      );

  factory MediaItem.fromLocal(LocalVideo v) => MediaItem(
        id: 'local:${v.uri}',
        title: v.name,
        subtitle: 'Op dit apparaat',
        uri: v.uri,
        kind: MediaKind.video,
      );
}
