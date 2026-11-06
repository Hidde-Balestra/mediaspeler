# Mediaspeler

Flutter-app voor podcasts en video's via RSS-feeds, en voor video's die op je eigen apparaat staan.

## Functies

- **Feeds**: RSS 2.0- en Atom-feeds toevoegen via hun URL. Audio- en video-afleveringen worden herkend aan `enclosure`, `media:content` of de bestandsextensie.
- **Afspelen**: audio en video via [media_kit](https://pub.dev/packages/media_kit), met mini-speler, 10 s terug / 30 s vooruit en afspeelsnelheid (0,75x tot 2x).
- **Verder waar je was**: de afspeelpositie wordt per aflevering/video bewaard; afgespeelde afleveringen krijgen de markering "beluisterd".
- **Op apparaat**: video's kiezen met de bestandskiezer en ze in een lokale bibliotheek bewaren.

## Platforms

Android, iOS en Windows.

## Starten

```sh
flutter pub get
flutter run
```

## Structuur

```
lib/
  main.dart                  app-start, thema
  models.dart                Feed, Episode, LocalVideo, MediaItem
  services/
    rss_service.dart         ophalen + parsen van RSS/Atom
    storage.dart             opslag (shared_preferences)
    app_state.dart           centrale status + speler
  screens/                   feeds, feed-detail, lokale video's, speler
  widgets/                   mini-speler, cover, opmaakhulpjes
```

## Bekende beperkingen

- Op Android wordt een gekozen video bewaard als `content://`-URI. Na een herstart kan de toegang daartoe vervallen; kies de video dan opnieuw.
- Op de achtergrond afspelen met bediening op het vergrendelscherm zit er nog niet in (daarvoor is bijvoorbeeld `audio_service` nodig).
- Feeds worden alleen vernieuwd als je een feed opent of op vernieuwen tikt.
