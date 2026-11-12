import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Opslag van covers en thumbnails op het apparaat: na het eerste keer laden
/// komen ze van de schijf (scheelt data en is sneller). Na een week ongebruikt
/// worden ze opgeruimd; daarna opnieuw opgehaald.
class AppImageCache {
  static const stalePeriod = Duration(days: 7);

  static final CacheManager manager = CacheManager(Config(
    'mediaspeler_images',
    stalePeriod: stalePeriod,
    maxNrOfCacheObjects: 1500,
  ));

  /// In tests (en op het web) gewoon NetworkImage: daar is geen bestandsopslag.
  static bool get _enabled =>
      !kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST');

  static ImageProvider provider(String url) => _enabled
      ? CachedNetworkImageProvider(url, cacheManager: manager)
      : NetworkImage(url);
}
