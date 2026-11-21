# GoliCat · গলির বিড়াল

A personal map companion: your real location on OpenStreetMap, shown as an animated
Dhaka street cat with a red scarf. Everything stays on your phone unless you turn on
**live sharing** (see below). There's no account and no public feed.

## Quickest way to see the office typing animation (no GPS needed)

1. Install and open the app.
2. Tap **Try the demo (no location needed)**.
3. Tap the first chip, **At work ⌨**. GoliCat is at the desk typing, and the
   Enter-key smash happens within about 4 seconds.
4. Tap the cat for the fish-cursor gag. Tap **Leave office** to watch it hang its glasses
   on the monitor and trot off. **Home 💤** shows the blanket nap (tap it there too).
5. Use **1× / 4× / 16×** to change the speed, and **End trip** to see the comic.

## Run it

Toolchain on this PC (installed under `E:\DevTools`, user env vars already set):
Flutter 3.50.1 stable, JDK 17, Android SDK (compileSdk 37).

```
cd E:\Projects\GoliCat
flutter pub get
flutter run                  # phone plugged in with USB debugging on
flutter build apk --release  # signed with the debug key for now (see "Release")
flutter test                 # engine, director, demo-script, UI and art tests
flutter analyze
```

A fresh clone needs `lib/config/seed_places.dart`. Copy `seed_places.example.dart` and
either fill in your places or leave them null. That file is git-ignored because it holds
your home and office.

## Map: OpenStreetMap (no key, no billing)

The map is OpenStreetMap through `flutter_map`, so there's no API key, no Google
billing and no card. Tiles come from `tile.openstreetmap.org` under its fair-use tile
policy, which is fine for one personal app. The app sends the User-Agent
`bd.golicat.golicat` and always shows "© OpenStreetMap contributors"; tapping it opens
the copyright page. Map rotation is off, so north stays up and street names stay upright.

If you ever want Google Maps instead, swap `TileLayer` in `lib/ui/map_screen.dart` for
the `google_maps_flutter` widget (it needs a key with billing enabled).

## How it works

```
lib/core/geo.dart                  distance, bearing, Mercator
lib/tracking/motion_engine.dart    noisy fixes → stationary / walking / fast (pure Dart)
lib/tracking/place_monitor.dart    office/home arrival & departure with hysteresis
lib/tracking/activity_engine.dart  combines them → CatMode
lib/tracking/location_service.dart geolocator stream, permission, sampling
lib/tracking/trip_runner.dart      the trip without UI (GPS → engine → journal → share)
lib/tracking/trip_service.dart     Android foreground service that hosts the runner
lib/cat/pose.dart, clips.dart      the character as a parameter vector + every animation
lib/cat/cat_director.dart          mode changes → visible transitions + tap gags
lib/cat/cat_painter.dart           hand-drawn rendering (all art is code)
lib/demo/…                         scripted outing + illustrated DEMO MAP
lib/ui/…                           map screen, place editor, demo, comic
```

Tunable defaults are in `lib/tracking/tuning.dart`:
- office radius 100 m (adjustable in the app, 30–400 m)
- exit ring = radius + max(30 m, 30%)
- arrival needs 2 minutes inside, with little net movement in the last minute
  (walking past doesn't count)
- departure needs 15 s beyond the exit ring
- fixes worse than 35 m never move the cat, and fixes worse than 50 m are ignored
  for office/home
- starting to move needs 3 consistent fixes outside the rest circle
- cha break after 60 s of stillness
- "fast" above 12 km/h (from speed only, with no guess at the vehicle)
- lost after 25 s without a reliable fix (50 s while sampling slowly)
- at the office or home, losing indoor GPS doesn't end Office or Home mode

## Background tracking (how a trip survives the app being closed)

Trips behave like Google Maps' location sharing: start one, close or swipe away
the app, lock the phone, and the cat keeps roaming and sharing until you end the trip.

- The trip never runs in the screen. `lib/tracking/trip_runner.dart` holds the whole
  pipeline (GPS → engine → journal → live share) with no UI, and reports a plain-map
  status once a second.
- **Android:** `lib/tracking/trip_service.dart` runs that runner inside a
  `flutter_background_service` foreground service of type `location`
  (`android:stopWithTask="false"`), with an ongoing "GoliCat is roaming with you"
  notification whose text follows the cat. The app's `TripController` (`lib/ui/`) only
  mirrors status events into `TripMirror` (the on-screen cat) and sends commands
  (`start`, `stop`, `startShare`, `stopShare`, `place`). On start the app sets the
  `tripRunning` pref and starts the service; the service reads that flag when it boots,
  so a start can't be lost and a service Android restarted resumes the saved journal.
  No `ACCESS_BACKGROUND_LOCATION` is requested; the service is what Android allows.
- **iOS / tests:** `LocalBackend` runs the same runner in-process (background location
  updates with the blue indicator on iOS).
- Reopening the app attaches to the running service. If the service is gone but a
  journal remains, the "trip was interrupted" dialog offers its comic.
- Trips stop by themselves after 24 h. Xiaomi/Redmi, Oppo, Vivo and Realme still kill
  services unless GoliCat has **Autostart** on and battery saver **No restrictions**;
  the settings sheet says so.

## Live location sharing

During a trip, tap the share-location button and pick 15 min, 1 h, 4 h or "until the
trip ends". The app makes a brand-new secret link and opens the share sheet. Anyone
with the link watches the cat live in their browser, with no app needed. The phone
sends its position every 5 s while moving, every 15 s while still, and right away when
the mode changes. If no update arrives for 75 s, viewers see "Last seen…" and the paper
map. Stopping the share, ending the trip or reaching the time limit deletes the
position from the server. The relay and viewer code is in `share/` (see `share/README.md`).

## Download counts

The download page itself shows the public numbers (total, last 7 days, today, countries,
a 30-day chart, and a count line under the button). They come from `/api/downloads`
(aggregates only, cached 60 s). The private page below shows more detail.

### Private dashboard

Private page: **https://golicat.yeasinfiyaz.workers.dev/stats/**. The password is in
`share/.stats-password` (git-ignored) and in the Cloudflare secret `STATS_PASSWORD`.
Change it with `echo NEWPASSWORD | ./deploy.sh secret put STATS_PASSWORD` in `share/`.

- The worker serves `/get/*` itself (`run_worker_first`) and counts, per Dhaka day and
  country: page visits, and APK downloads by version and phone type. Only the first piece
  of a download counts, and bots, link previews (WhatsApp, Messenger, Telegram), curl and
  headless browsers are skipped.
- "People" uses a one-way code salted per day (`STATS_SALT`), so no IPs or device IDs
  are stored. Those codes are deleted after 90 days. Counting started 21 Nov 2026.
- Totals live in the `Stats` Durable Object (SQLite). The page is `share/site/stats/`.
- When testing, send the header `x-golicat-nocount: 1` so checks never count.
- Local: put `STATS_PASSWORD=...` and `STATS_SALT=...` in `share/.dev.vars` (git-ignored).

## Privacy

The office, home, settings and the in-progress trip journal live in SharedPreferences on
the device. The trip journal and the comic contain moments, duration and distance only,
never coordinates, routes or addresses.

## Logo and character

The logo (white cat, orange patches, happy closed eyes, red scarf) was approved on
21 Nov 2026. Master vector: `branding/logo_d_face.svg` (badge) and `logo_d_nobadge.svg`
(transparent), also in the user's Figma file "GoliCat Logo". `branding/` holds the
other explored directions (A–C tabby, E sitting) and `preview.html`. Icon PNGs
(`assets/icon/icon.png`, `icon_fg.png`, `web/icons`, `web/og.png`, `share/site/get/img/icon.png`)
were rasterised from the SVG with Chrome headless (`--default-background-color=00000000`);
re-run `dart run flutter_launcher_icons` after changing them. The in-app animated cat
(`lib/cat/cat_painter.dart`) uses the same palette (`CatInk`): white fur, orange patches
instead of tabby stripes, blush, ∩ eyes when closed.

## Release and publishing

- Download page (public): **https://golicat.yeasinfiyaz.workers.dev/get/** with the privacy
  policy at `/privacy/`. Pages live in `share/site/`.
- `bash share/publish.sh` does everything: builds the PUBLIC app (release-signed, with the
  empty `seed_places.example.dart` so nobody's home/office is inside), builds the web
  viewer, fills in version/size/SHA-256 on the page and deploys. Bump `version:` in
  pubspec.yaml first.
- Signing key: `android/keystore/golicat-release.jks` + `android/key.properties`
  (git-ignored). Backup in `Documents\GoliCat signing key (BACKUP)`. Losing it means
  people can't update over the old install.
- Your own phone keeps the seeded build: `flutter build apk --release --target-platform
  android-arm64` (same signing key, so it updates over the public one too).
- Version numbering restarted at **1.0.0** for the first public release (21 Nov 2026).
  The build number after `+` must still go up every release (it was 7), or phones refuse the update.
- `NO_DEPLOY=1 bash share/publish.sh` builds everything without deploying, for testing first.
- Google Play Protect shows "App scan recommended" for any APK it hasn't seen. No code
  change removes it. Tapping **Scan app** once sends that exact file to Google, and
  publishing the same file afterwards helps. The real fix is Google Play, or Google's
  Android developer verification when it reaches Bangladesh.
- The trip service creates its notification channel in `GoliCatApp.kt`. Without it,
  Start roaming crashed the app (1.5.0). The plugin's boot receiver and the
  `RECEIVE_BOOT_COMPLETED` permission are removed, and its service is not exported.
- Google Play: not done. Needs a $25 developer account, a 12-tester closed test for 14 days,
  then the Data safety form (location, live-share) and this privacy policy URL.
