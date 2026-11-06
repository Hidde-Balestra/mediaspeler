/// Datamodellen voor feeds, afleveringen en lokale video's.
library;

enum MediaKind { audio, video }

class Feed {
  final String url;
  final String title;
  final String? description;
  final String? imageUrl;
  final DateTime? lastFetched;

  const Feed({
    required this.url,
    required this.title,
    this.description,
    this.imageUrl,
    this.lastFetched,
  });

  Feed copyWith({
    String? title,
    String? description,
    String? imageUrl,
    DateTime? lastFetched,
  }) =>
      Feed(
        url: url,
        title: title ?? this.title,
        description: description ?? this.description,
        imageUrl: imageUrl ?? this.imageUrl,
        lastFetched: lastFetched ?? this.lastFetched,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'description': description,
        'imageUrl': imageUrl,
        'lastFetched': lastFetched?.toIso8601String(),
      };

  factory Feed.fromJson(Map<String, dynamic> j) => Feed(
        url: j['url'] as String,
        title: j['title'] as String? ?? j['url'] as String,
        description: j['description'] as String?,
        imageUrl: j['imageUrl'] as String?,
        lastFetched: j['lastFetched'] != null
            ? DateTime.tryParse(j['lastFetched'] as String)
            : null,
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

  MediaKind get kind {
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

  const MediaItem({
    required this.id,
    required this.title,
    required this.uri,
    required this.kind,
    this.subtitle,
    this.imageUrl,
  });

  factory MediaItem.fromEpisode(Episode e, {String? feedTitle}) => MediaItem(
        id: e.id,
        title: e.title,
        subtitle: feedTitle,
        uri: e.mediaUrl,
        kind: e.kind,
        imageUrl: e.imageUrl,
      );

  factory MediaItem.fromLocal(LocalVideo v) => MediaItem(
        id: 'local:${v.uri}',
        title: v.name,
        subtitle: 'Op dit apparaat',
        uri: v.uri,
        kind: MediaKind.video,
      );
}
