import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// Eenvoudige opslag via shared_preferences: abonnementen, lokale video's
/// en afspeelposities (zodat je verder kunt waar je gebleven was).
class Storage {
  static const _feedsKey = 'feeds';
  static const _localKey = 'local_videos';
  static const _posPrefix = 'pos:';
  static const _doneKey = 'finished';
  static const _themeKey = 'theme_mode';
  static const _episodesPrefix = 'eps:';
  static const _lastKey = 'last_played';

  final SharedPreferences _prefs;
  Storage._(this._prefs);

  static Future<Storage> open() async => Storage._(await SharedPreferences.getInstance());

  List<Feed> loadFeeds() => _loadList(_feedsKey, Feed.fromJson);
  Future<void> saveFeeds(List<Feed> feeds) =>
      _prefs.setString(_feedsKey, jsonEncode(feeds.map((f) => f.toJson()).toList()));

  List<LocalVideo> loadLocalVideos() => _loadList(_localKey, LocalVideo.fromJson);
  Future<void> saveLocalVideos(List<LocalVideo> videos) =>
      _prefs.setString(_localKey, jsonEncode(videos.map((v) => v.toJson()).toList()));

  /// Laatst opgehaalde afleveringen per feed, zodat lijsten direct (en offline) gevuld zijn.
  List<Episode> loadEpisodes(String feedUrl) =>
      _loadList('$_episodesPrefix$feedUrl', Episode.fromJson);
  Future<void> saveEpisodes(String feedUrl, List<Episode> episodes) => _prefs.setString(
      '$_episodesPrefix$feedUrl', jsonEncode(episodes.map((e) => e.toJson()).toList()));
  Future<void> clearEpisodes(String feedUrl) => _prefs.remove('$_episodesPrefix$feedUrl');

  /// Laatst gespeelde item, voor "Verder luisteren" na een herstart.
  MediaItem? lastPlayed() {
    final raw = _prefs.getString(_lastKey);
    if (raw == null) return null;
    try {
      return MediaItem.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> setLastPlayed(MediaItem? item) => item == null
      ? _prefs.remove(_lastKey)
      : _prefs.setString(_lastKey, jsonEncode(item.toJson()));

  Duration? position(String id) {
    final ms = _prefs.getInt('$_posPrefix$id');
    return ms == null ? null : Duration(milliseconds: ms);
  }

  Future<void> savePosition(String id, Duration pos) =>
      _prefs.setInt('$_posPrefix$id', pos.inMilliseconds);

  Future<void> clearPosition(String id) => _prefs.remove('$_posPrefix$id');

  Set<String> finished() => (_prefs.getStringList(_doneKey) ?? const []).toSet();

  Future<void> setFinished(String id, bool done) {
    final set = finished();
    done ? set.add(id) : set.remove(id);
    return _prefs.setStringList(_doneKey, set.toList());
  }

  /// Thema-voorkeur: 'system', 'light' of 'dark'.
  String? themeMode() => _prefs.getString(_themeKey);
  Future<void> setThemeMode(String mode) => _prefs.setString(_themeKey, mode);

  List<T> _loadList<T>(String key, T Function(Map<String, dynamic>) fromJson) {
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
