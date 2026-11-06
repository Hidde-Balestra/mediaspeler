# Mediaspeler

Flutter-app voor podcasts en video's via RSS-feeds, en voor video's die op je eigen apparaat staan.

## Functies

- **Feeds**: RSS 2.0- en Atom-feeds toevoegen via hun URL. Audio- en video-afleveringen worden herkend aan `enclosure`, `media:content` of de bestandsextensie.
- **Afspelen**: audio en video via [media_kit](https://pub.dev/packages/media_kit), met mini-speler, 10 s terug / 30 s vooruit en afspeelsnelheid (0,75x tot 2x).
- **Verder waar je was**: de afspeelpositie wordt per aflevering/video bewaard; afgespeelde afleveringen krijgen de markering "beluisterd".
- **Op apparaat**: video's kiezen met de bestandskiezer en ze in een lokale bibliotheek bewaren.
- **Thema**: licht, donker of systeem volgen; te kiezen via het thema-icoon rechtsboven en bewaard tussen sessies.
- **Op de achtergrond**: afspelen gaat door als de app op de achtergrond staat of het scherm uit is, met bediening via de melding, het vergrendelscherm en koptelefoonknoppen (Android en iOS, via `audio_service`). Op Windows speelt de app op de achtergrond gewoon door.

## Platforms

Android, iOS en Windows.

## Starten

```sh
flutter pub get
flutter run
```

## Testen

```sh
flutter analyze
flutter test
```

De tests staan in `test/` en dekken de modellen, de opslag, het parsen en ophalen van feeds, de app-status (feeds, lokale video's, thema) en een paar widget-tests (lege schermen, thema wisselen, foutmelding bij toevoegen).

## CI en releases

- `.github/workflows/ci.yml` draait `flutter analyze` en `flutter test` bij elke push naar `main` en elke pull request.
- `.github/workflows/release.yml` bouwt een APK en zet die in een GitHub-release. Starten door een tag te pushen:

  ```sh
  git tag v1.0.0
  git push origin v1.0.0
  ```

  De versie komt uit de tag, het buildnummer uit het run-nummer. Een tag met een streepje (bijv. `v1.1.0-beta`) wordt een pre-release.

### Eigen signing-sleutel (aanbevolen)

Vanaf v1.1.0 zijn de secrets ingesteld en wordt de APK met een eigen sleutel getekend. Zonder sleutel valt de workflow terug op de debug-sleutel. Dat werkt, maar Android accepteert een update dan niet als je later naar een eigen sleutel overstapt. Maak eenmalig een keystore aan en zet deze repository-secrets:

```sh
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
base64 -w0 upload-keystore.jks   # waarde voor ANDROID_KEYSTORE_BASE64
```

| Secret | Waarde |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | de keystore, base64 |
| `ANDROID_KEYSTORE_PASSWORD` | wachtwoord van de keystore |
| `ANDROID_KEY_ALIAS` | bijv. `upload` |
| `ANDROID_KEY_PASSWORD` | wachtwoord van de sleutel |

Lokaal kun je hetzelfde doen met een `android/key.properties` (staat in `.gitignore`).

## Structuur

```
lib/
  main.dart                  app-start, thema
  models.dart                Feed, Episode, LocalVideo, MediaItem
  services/
    rss_service.dart         ophalen + parsen van RSS/Atom
    storage.dart             opslag (shared_preferences)
    app_state.dart           centrale status + speler
    media_session.dart       koppeling met de systeem-mediasessie
  screens/                   feeds, feed-detail, lokale video's, speler
  widgets/                   mini-speler, cover, opmaakhulpjes
```

## Bekende beperkingen

- Op Android wordt een gekozen video bewaard als `content://`-URI. Na een herstart kan de toegang daartoe vervallen; kies de video dan opnieuw.
- Feeds worden alleen vernieuwd als je een feed opent of op vernieuwen tikt.
