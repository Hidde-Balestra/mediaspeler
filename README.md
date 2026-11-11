# Mediaspeler

Flutter-app voor podcasts en video's via RSS-feeds, en voor video's die op je eigen apparaat staan.

## Functies

- **Toevoegen of zoeken**: één invoerveld voor alles. Herkent RSS/Atom-feeds, YouTube, **Spotify** (zoekt de gewone RSS-versie van de podcast op; bij een link naar een aflevering speelt die meteen af), **Apple Podcasts** en **Overcast**, websites (feed op de pagina, link naar Apple Podcasts, of zoeken op de naam van de site) en losse audio-/videolinks (direct afspelen). Of typ een naam om in de podcastgids te zoeken. Spotify-exclusieve podcasts kunnen niet buiten Spotify spelen: dan krijg je de knop "Open in Spotify".
- **Nieuw**: alle afleveringen en video's van al je feeds bij elkaar, nieuwste eerst, met filters (podcasts/video's, verberg beluisterd). Afleveringen worden bewaard, dus de lijst is ook offline direct gevuld.
- **Afspelen**: audio en video via [media_kit](https://pub.dev/packages/media_kit), met mini-speler, 10 s terug / 30 s vooruit en afspeelsnelheid (0,75x tot 2x).
- **Verder waar je was**: de afspeelpositie wordt per aflevering/video bewaard (elke 5 s, en meteen bij pauzeren, scherm uit of app sluiten) en bij opnieuw afspelen hervat. Na een herstart staat onderin "Verder vanaf …". Een verlopen YouTube-stream wordt automatisch opnieuw opgehaald, vanaf dezelfde plek.
- **Op apparaat**: video's kiezen met de bestandskiezer en ze in een lokale bibliotheek bewaren.
- **YouTube**: een kanaal (`youtube.com/@naam`, `@naam`, `/channel/UC…`) of playlist toevoegen via hetzelfde invoerveld. Met **Afspelen als podcast** wordt alleen de audio opgehaald (zuinigste stream tot 96 kbit/s, meestal 70–90% minder data dan video). Per kanaal om te zetten via het koptelefoon-icoon; per video kun je ook kiezen voor "Video bekijken" of "Open in YouTube".
  - **Podcastversie eerst**: kies je "Afspelen als podcast", dan zoekt de app in de openbare podcastgids van Apple of het kanaal ook een gewone podcastfeed heeft (op kanaalnaam én @handle). Gevonden? Dan krijg je die als voorstel: echte audio, werkt op de achtergrond, geen blokkades. Voor kanalen die je al volgt: podcast-icoon in het kanaal.
  - **Lukt alleen-audio niet** (YouTube's bot-controle), dan probeert de app het één keer opnieuw na een korte pauze en laat YouTube daarna 15 minuten met rust. In die tijd, of als het echt niet lukt, speelt de video via de **officiële YouTube-speler** in de app (met beeld, alleen zolang het scherm open is; op Windows in de browser).
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
    youtube_service.dart     YouTube-kanalen → RSS, streams ophalen
    podcast_directory.dart   podcastversie zoeken (iTunes Search API)
    source_resolver.dart     links herkennen: Spotify, Apple, websites, mediabestanden
  screens/                   feeds, feed-detail, lokale video's, speler
  widgets/                   mini-speler, cover, opmaakhulpjes
```

## Bekende beperkingen

- Op Android wordt een gekozen video bewaard als `content://`-URI. Na een herstart kan de toegang daartoe vervallen; kies de video dan opnieuw.
- Feeds worden alleen vernieuwd als je een feed opent of op vernieuwen tikt.
- YouTube: de lijst met video's komt uit YouTube's officiële RSS-feed (de laatste 15 video's per kanaal). Het afspelen gebruikt [youtube_explode_dart](https://pub.dev/packages/youtube_explode_dart) en werkt niet altijd: YouTube kan het ophalen tijdelijk blokkeren ("bot-controle"), vooral bij veel verzoeken of bij recente video's. De app valt dan terug op de officiële YouTube-speler. Dit gebruik valt buiten de gebruiksvoorwaarden van YouTube; bedoeld voor persoonlijk gebruik.
- YouTube-video's met beeld spelen in maximaal 360p (de enige streams met beeld én geluid samen).
- Via de officiële YouTube-speler (de terugval) speelt een video niet door op het vergrendelscherm: dat staat YouTube voor ingesloten spelers niet toe. Alleen-audio via de eigen speler speelt wel door. De plek wordt in beide gevallen onthouden.

## App-icoon

Het icoon wordt getekend in [tool/render_icon_test.dart](tool/render_icon_test.dart). Aanpassen en opnieuw genereren:

```sh
flutter test tool/render_icon_test.dart
dart run flutter_launcher_icons
git checkout ios/Runner.xcodeproj/project.pbxproj   # het tool zet daar een verkeerde waarde
```
